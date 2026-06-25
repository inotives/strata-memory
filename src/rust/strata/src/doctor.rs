use crate::index::model::IndexBackend;
use crate::{
    absolute_path, collect_markdown_files_rec, config, index, json_escape, rel_path, review, Result,
};
use rusqlite::{params, Connection, OptionalExtension};
use std::fs::{self, OpenOptions};
use std::path::Path;
use std::process::Command;

const BOOTSTRAP_DEPENDENCIES: &[&str] = &[
    "bash", "sqlite3", "awk", "sed", "find", "sort", "mktemp", "cksum", "date",
];
const REQUIRED_DIRS: &[&str] = &[
    "0_core/config",
    "0_core/cache",
    "0_core/db",
    "0_core/script",
    "0_core/template",
    "0_core/tmp",
    "1_draft",
    "2_knowledge",
    "3_intelligence",
];
const VALID_STATUSES: &[&str] = &["pending", "verified", "archived", "generated", "core"];

#[derive(Debug)]
struct Check {
    status: &'static str,
    name: &'static str,
    message: String,
}

pub(crate) fn run(vault: &Path, json: bool) -> Result<()> {
    let mut checks = Vec::new();
    let index_info = index::configured(vault).ok();
    fs::create_dir_all(vault.join("0_core/tmp"))?;

    record_dependencies(&mut checks);
    record_directories(vault, &mut checks);
    record_writable(vault, "0_core/tmp", "tmp_writable", &mut checks);
    record_writable(vault, "0_core/db", "db_writable", &mut checks);
    record_config(vault, &mut checks);
    record_database(vault, &mut checks);
    record_status_review(vault, &mut checks)?;
    record_review_counts(vault, &mut checks);
    record_agents(vault, &mut checks);

    let passes = checks.iter().filter(|check| check.status == "pass").count();
    let warnings = checks.iter().filter(|check| check.status == "warn").count();
    let errors = checks
        .iter()
        .filter(|check| check.status == "error")
        .count();

    if json {
        let backend = index_info
            .as_ref()
            .map(|info| info.backend.to_string())
            .unwrap_or_else(|| "unknown".to_string());
        let experimental = index_info
            .as_ref()
            .map(|info| info.experimental)
            .unwrap_or(false);
        print!(
            "{{\"ok\":{},\"backend\":\"{}\",\"experimental\":{},\"passes\":{},\"warnings\":{},\"errors\":{},\"checks\":[",
            if errors == 0 { "true" } else { "false" },
            backend,
            experimental,
            passes,
            warnings,
            errors
        );
        for (idx, check) in checks.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            print!(
                "{{\"status\":\"{}\",\"name\":\"{}\",\"message\":\"{}\"}}",
                json_escape(check.status),
                json_escape(check.name),
                json_escape(&check.message)
            );
        }
        println!("]}}");
    } else {
        println!("Strata doctor: {passes} pass, {warnings} warning, {errors} error");
        for check in &checks {
            println!("{} {} - {}", check.status, check.name, check.message);
        }
    }

    if errors > 0 {
        return Err(format!("doctor found {errors} error(s)").into());
    }
    Ok(())
}

fn record_dependencies(checks: &mut Vec<Check>) {
    let missing_bootstrap = missing_dependencies(BOOTSTRAP_DEPENDENCIES);
    if missing_bootstrap.is_empty() {
        checks.push(pass(
            "bootstrap_dependencies",
            "bootstrap dependencies are available",
        ));
    } else {
        checks.push(error(
            "bootstrap_dependencies",
            &format!(
                "Missing bootstrap dependencies: {}",
                missing_bootstrap.join(" ")
            ),
        ));
    }
}

fn record_directories(vault: &Path, checks: &mut Vec<Check>) {
    for rel in REQUIRED_DIRS {
        if vault.join(rel).is_dir() {
            checks.push(pass("directory", &format!("{rel} exists")));
        } else {
            checks.push(error("directory", &format!("{rel} is missing")));
        }
    }
}

fn record_writable(vault: &Path, rel: &str, name: &'static str, checks: &mut Vec<Check>) {
    let dir = vault.join(rel);
    if !dir.is_dir() {
        return;
    }
    let probe = dir.join(format!(".doctor-write-{}", std::process::id()));
    match OpenOptions::new().write(true).create_new(true).open(&probe) {
        Ok(_) => {
            let _ = fs::remove_file(&probe);
            checks.push(pass(name, &format!("{rel} is writable")));
        }
        Err(_) => checks.push(error(
            name,
            &format!("{rel} is not writable; check filesystem mount state before SQLite rebuilds"),
        )),
    }
}

fn record_config(vault: &Path, checks: &mut Vec<Check>) {
    if vault.join("0_core/config/configs.yaml").is_file() {
        checks.push(pass("config", "0_core/config/configs.yaml exists"));
        match config::profile_tier2_rooms(vault) {
            Ok((profile, _)) if !profile.is_empty() => {
                checks.push(pass("profile", &format!("active profile is {profile}")));
            }
            Ok(_) => checks.push(error("profile", "active profile is missing")),
            Err(err) => checks.push(error("profile", &err.to_string())),
        }
    } else {
        checks.push(error("config", "0_core/config/configs.yaml is missing"));
    }

    if vault.join("0_core/cache/config.compiled.json").is_file() {
        checks.push(pass(
            "config_cache",
            "0_core/cache/config.compiled.json exists",
        ));
    } else {
        checks.push(warn(
            "config_cache",
            "0_core/cache/config.compiled.json is missing; run strata config-compile",
        ));
    }
}

fn record_database(vault: &Path, checks: &mut Vec<Check>) {
    let info = match index::configured(vault) {
        Ok(info) => info,
        Err(err) => {
            checks.push(error("index_backend", &err.to_string()));
            return;
        }
    };
    let inactive = match info.backend {
        IndexBackend::Sqlite => vault.join("0_core/db/strata-turso.db"),
        IndexBackend::Turso => vault.join("0_core/db/strata.db"),
    };
    if let Ok(metadata) = fs::metadata(&inactive) {
        checks.push(pass(
            "inactive_database",
            &format!(
                "{} retained ({} bytes)",
                inactive
                    .strip_prefix(vault)
                    .unwrap_or(&inactive)
                    .to_string_lossy(),
                metadata.len()
            ),
        ));
    }
    if info.backend == IndexBackend::Turso {
        checks.push(warn(
            "index_backend",
            "active index backend is experimental Turso",
        ));
        let db_path = info.db_path;
        if !db_path.is_file() {
            checks.push(error(
                "database",
                "0_core/db/strata-turso.db is missing; run strata db-migrate",
            ));
            return;
        }
        checks.push(pass("database", "0_core/db/strata-turso.db exists"));
        match index::turso_migrations(vault) {
            Ok(versions) => {
                checks.push(pass("schema", "Turso schema_migrations is readable"));
                for version in ["001", "002", "003"] {
                    if versions.iter().any(|applied| applied == version) {
                        checks.push(pass(
                            match version {
                                "001" => "migration_001",
                                "002" => "migration_002",
                                _ => "migration_003",
                            },
                            &format!("Turso migration {version} is applied"),
                        ));
                    } else {
                        checks.push(error(
                            match version {
                                "001" => "migration_001",
                                "002" => "migration_002",
                                _ => "migration_003",
                            },
                            &format!("Turso migration {version} is not applied"),
                        ));
                    }
                }
            }
            Err(err) => checks.push(error("schema", &err.to_string())),
        }
        return;
    }

    checks.push(pass("index_backend", "active index backend is sqlite"));
    let db_path = info.db_path;
    if !db_path.is_file() {
        checks.push(error(
            "database",
            "0_core/db/strata.db is missing; run strata db-migrate",
        ));
        return;
    }

    checks.push(pass("database", "0_core/db/strata.db exists"));
    let Ok(conn) = Connection::open(&db_path) else {
        checks.push(error("schema", "schema_migrations is not readable"));
        return;
    };

    if conn
        .query_row("SELECT 1 FROM schema_migrations LIMIT 1", [], |_| Ok(()))
        .is_ok()
    {
        checks.push(pass("schema", "schema_migrations is readable"));
        if has_migration(&conn, "001") {
            checks.push(pass("migration_001", "migration 001 is applied"));
        } else {
            checks.push(error("migration_001", "migration 001 is not applied"));
        }
        if sqlite_supports_fts5() {
            if has_migration(&conn, "002") {
                checks.push(pass("migration_002", "FTS5 migration 002 is applied"));
            } else {
                checks.push(error(
                    "migration_002",
                    "SQLite supports FTS5 but migration 002 is not applied",
                ));
            }
        } else {
            checks.push(warn(
                "migration_002",
                "SQLite FTS5 is unavailable; FTS5 migration is skipped",
            ));
        }
    } else {
        checks.push(error("schema", "schema_migrations is not readable"));
    }
}

fn record_status_review(vault: &Path, checks: &mut Vec<Check>) -> Result<()> {
    let invalid = invalid_status_count(vault)?;
    if invalid == 0 {
        checks.push(pass("status_review", "all frontmatter statuses are valid"));
    } else {
        checks.push(error(
            "status_review",
            &format!("{invalid} invalid frontmatter statuses found"),
        ));
    }
    Ok(())
}

fn record_review_counts(vault: &Path, checks: &mut Vec<Check>) {
    match review::unknown_tag_count(vault) {
        Ok(0) => checks.push(pass("tag_review", "no unknown tags")),
        Ok(count) => checks.push(warn(
            "tag_review",
            &format!("{count} unknown or similar tags found"),
        )),
        Err(_) => checks.push(error("tag_review", "strata tag-review failed")),
    }

    match review::unregistered_room_count(vault) {
        Ok(0) => checks.push(pass("room_review", "no unregistered rooms")),
        Ok(count) => checks.push(warn(
            "room_review",
            &format!("{count} unregistered rooms found"),
        )),
        Err(_) => checks.push(error("room_review", "strata room-review failed")),
    }

    match review::link_review_counts(vault) {
        Ok((0, _)) => checks.push(pass("link_review", "no link issues")),
        Ok((issue_count, 0)) => checks.push(warn(
            "link_review",
            &format!("{issue_count} draft link warnings found"),
        )),
        Ok((_, error_count)) => checks.push(error(
            "link_review",
            &format!("{error_count} durable link errors found"),
        )),
        Err(_) => checks.push(error("link_review", "strata link-review failed")),
    }
}

fn record_agents(vault: &Path, checks: &mut Vec<Check>) {
    let agents = vault.join("AGENTS.md");
    let Ok(content) = fs::read_to_string(&agents) else {
        checks.push(error(
            "agents",
            "AGENTS.md is missing; run strata agents-generate",
        ));
        return;
    };
    if content.contains("<!-- STRATA_GENERATED_START -->")
        && content.contains("<!-- STRATA_MANUAL_START -->")
    {
        checks.push(pass(
            "agents",
            "AGENTS.md exists with generated and manual markers",
        ));
    } else {
        checks.push(warn(
            "agents",
            "AGENTS.md exists but generated/manual markers are incomplete",
        ));
    }
}

fn invalid_status_count(vault: &Path) -> Result<usize> {
    let mut files = Vec::new();
    for rel in ["1_draft", "2_knowledge", "3_intelligence"] {
        let root = vault.join(rel);
        if root.is_dir() {
            collect_markdown_files_rec(&root, &mut files)?;
        }
    }
    files.sort();

    let mut invalid = 0;
    for file in files {
        let abs = absolute_path(&file)?;
        let Some(_rel) = rel_path(&abs, vault) else {
            continue;
        };
        let content = fs::read_to_string(&abs)?;
        if let Some(status) = frontmatter_status(&content) {
            if !VALID_STATUSES.contains(&status.as_str()) {
                invalid += 1;
            }
        }
    }
    Ok(invalid)
}

fn frontmatter_status(content: &str) -> Option<String> {
    let mut lines = content.lines();
    if lines.next() != Some("---") {
        return None;
    }
    for line in lines {
        if line == "---" {
            return None;
        }
        if let Some(value) = line.strip_prefix("status:") {
            return Some(value.trim().trim_matches('"').to_string());
        }
    }
    None
}

fn has_migration(conn: &Connection, version: &str) -> bool {
    let found: rusqlite::Result<Option<String>> = conn
        .query_row(
            "SELECT version FROM schema_migrations WHERE version = ?1 LIMIT 1",
            params![version],
            |row| row.get(0),
        )
        .optional();
    matches!(found, Ok(Some(value)) if value == version)
}

fn sqlite_supports_fts5() -> bool {
    let Ok(conn) = Connection::open_in_memory() else {
        return false;
    };
    conn.execute_batch("CREATE VIRTUAL TABLE strata_fts5_check USING fts5(content);")
        .is_ok()
}

fn missing_dependencies<'a>(dependencies: &'a [&'a str]) -> Vec<&'a str> {
    dependencies
        .iter()
        .copied()
        .filter(|dependency| !command_exists(dependency))
        .collect()
}

fn command_exists(command: &str) -> bool {
    Command::new("sh")
        .arg("-c")
        .arg("command -v \"$1\" >/dev/null 2>&1")
        .arg("sh")
        .arg(command)
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn pass(name: &'static str, message: &str) -> Check {
    check("pass", name, message)
}

fn warn(name: &'static str, message: &str) -> Check {
    check("warn", name, message)
}

fn error(name: &'static str, message: &str) -> Check {
    check("error", name, message)
}

fn check(status: &'static str, name: &'static str, message: &str) -> Check {
    Check {
        status,
        name,
        message: message.to_string(),
    }
}
