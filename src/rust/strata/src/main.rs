mod agents;
mod cli;
mod config;
mod db;
mod lifecycle;
mod review;
mod vault;

use cli::{Command, IndexMode, SearchArgs};
use rusqlite::{params, Connection, Transaction};
use std::collections::{HashMap, HashSet};
use std::env;
use std::error::Error;
use std::fs;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

#[derive(Debug)]
struct Document {
    id: String,
    path: String,
    title: String,
    description: String,
    strata: String,
    status: String,
    tags: String,
    sources: String,
    source_note: String,
    version: i64,
    last_edit_summary: String,
    created: String,
    modified: String,
    content: String,
    content_hash: String,
}

#[derive(Debug)]
struct Link {
    target: String,
    target_type: String,
    text: String,
    line: i64,
}

#[derive(Debug)]
struct Section {
    heading: String,
    level: i64,
    start_line: i64,
    end_line: i64,
    content: String,
}

fn main() {
    match run() {
        Ok(()) => {}
        Err(err) => {
            eprintln!("strata: {err}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<()> {
    let cli = cli::parse_args(env::args().skip(1).collect())?;

    match cli.command {
        Command::AgentsGenerate => {
            let summary = agents::generate(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"path\":\"{}\",\"profile\":\"{}\"}}",
                    json_escape(&summary.path),
                    json_escape(&summary.profile)
                );
            } else {
                println!("Generated AGENTS.md for profile: {}", summary.profile);
            }
        }
        Command::Index(mode) => {
            let indexed = index(&cli.vault, mode)?;
            if cli.json {
                println!("{{\"ok\":true,\"indexed\":{indexed}}}");
            } else {
                println!("Indexed {indexed} file(s)");
            }
        }
        Command::Search(search_args) => {
            search(&cli.vault, &search_args, cli.json)?;
        }
        Command::LinkReview => {
            review::link_review(&cli.vault, cli.json)?;
        }
        Command::PrivacyReview => {
            review::privacy_review(&cli.vault, cli.json)?;
        }
        Command::TagReview => {
            review::tag_review(&cli.vault, cli.json)?;
        }
        Command::DbMigrate => {
            let applied = db::migrate(&cli.vault)?;
            let db_path = cli.vault.join("0_core/db/strata.db");
            if cli.json {
                println!(
                    "{{\"ok\":true,\"db\":\"{}\",\"applied\":{applied}}}",
                    json_escape(&db_path.to_string_lossy())
                );
            } else {
                println!(
                    "Database migrated: {} ({applied} applied)",
                    db_path.to_string_lossy()
                );
            }
        }
        Command::Init => {
            vault::init(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"vault\":\"{}\"}}",
                    json_escape(&cli.vault.to_string_lossy())
                );
            } else {
                println!(
                    "Initialized Strata-Memory vault: {}",
                    cli.vault.to_string_lossy()
                );
            }
        }
        Command::ConfigCompile => {
            let summary = config::compile(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"cache\":\"{}\",\"profile\":\"{}\",\"rooms\":{},\"tags\":{}}}",
                    json_escape(&summary.cache.to_string_lossy()),
                    json_escape(&summary.profile),
                    summary.rooms,
                    summary.tags
                );
            } else {
                println!("Compiled config: {}", summary.cache.to_string_lossy());
            }
        }
        Command::Normalize(args) => {
            match lifecycle::normalize(&cli.vault, &args.target, args.check) {
                Ok(summary) => {
                    if cli.json {
                        println!(
                            "{{\"ok\":true,\"path\":\"{}\",\"strata\":\"{}\",\"status\":\"{}\"}}",
                            json_escape(&summary.path),
                            json_escape(&summary.strata),
                            json_escape(&summary.status)
                        );
                    } else if args.check {
                        println!("Normalized check passed: {}", summary.path);
                    } else {
                        println!("Normalized: {}", summary.path);
                    }
                }
                Err(err) if cli.json && err.to_string().contains("description is required") => {
                    let abs = absolute_path(&args.target)?;
                    let rel = rel_path(&abs, &cli.vault)
                        .unwrap_or_else(|| abs.to_string_lossy().to_string());
                    println!(
                        "{{\"ok\":false,\"error\":\"description_required\",\"path\":\"{}\"}}",
                        json_escape(&rel)
                    );
                    return Err(err);
                }
                Err(err) => return Err(err),
            }
        }
        Command::Promote(args) => {
            let summary =
                lifecycle::promote(&cli.vault, &args.source, &args.to, args.new_slug.as_deref())?;
            index(
                &cli.vault,
                IndexMode::Target(cli.vault.join(&summary.target)),
            )?;
            index(
                &cli.vault,
                IndexMode::Target(cli.vault.join(&summary.archive)),
            )?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"target\":\"{}\",\"archive\":\"{}\",\"log\":\"{}\"}}",
                    json_escape(&summary.target),
                    json_escape(&summary.archive),
                    json_escape(&summary.log)
                );
            } else {
                println!("Promoted: {}", summary.target);
                println!("Archived: {}", summary.archive);
            }
        }
        Command::Retention(args) => {
            let summary = lifecycle::retention(&cli.vault, args.apply)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"report\":\"{}\",\"mode\":\"{}\",\"candidate_count\":{},\"deleted_count\":{},\"kept_count\":{},\"skipped_count\":{}}}",
                    json_escape(&summary.report),
                    json_escape(&summary.mode),
                    summary.candidate_count,
                    summary.deleted_count,
                    summary.kept_count,
                    summary.skipped_count
                );
            } else {
                println!(
                    "Retention {} complete: {} candidate, {} deleted, {} kept, {} skipped",
                    summary.mode,
                    summary.candidate_count,
                    summary.deleted_count,
                    summary.kept_count,
                    summary.skipped_count
                );
                println!("Report: {}", summary.report);
            }
        }
    }

    Ok(())
}

fn index(vault: &Path, mode: IndexMode) -> Result<usize> {
    db::migrate(vault)?;

    let db_path = vault.join("0_core/db/strata.db");
    let mut conn = Connection::open(db_path)?;

    match mode {
        IndexMode::Full => index_full(&mut conn, vault),
        IndexMode::Target(target) => {
            let tx = conn.transaction()?;
            let indexed = index_one(&tx, vault, &target)?;
            tx.commit()?;
            Ok(indexed)
        }
    }
}

fn search(vault: &Path, args: &SearchArgs, json: bool) -> Result<()> {
    let db_path = vault.join("0_core/db/strata.db");
    if !db_path.is_file() {
        return Err("database not found; run index.sh first".into());
    }

    let conn = Connection::open(db_path)?;
    if args.paths_only {
        let mut sql = String::from(
            "SELECT memory_index.path
FROM memory_fts
JOIN memory_index ON memory_fts.rowid = memory_index.rowid
WHERE memory_fts MATCH ?1",
        );
        if !args.include_archived {
            sql.push_str(" AND memory_index.status <> 'archived'");
        }
        sql.push_str(
            "
ORDER BY bm25(memory_fts, 8.0, 4.0, 2.0, 1.0)
LIMIT ?2",
        );

        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params![args.query, args.limit as i64], |row| {
            row.get::<_, String>(0)
        })?;
        for row in rows {
            println!("{}", row?);
        }
        return Ok(());
    }

    let mut sql = String::from(
        "SELECT memory_index.path,
       ifnull(memory_index.title,''),
       memory_index.status,
       printf('%.6f', bm25(memory_fts, 8.0, 4.0, 2.0, 1.0)),
       replace(replace(snippet(memory_fts, 3, '[', ']', '...', 12), char(10), ' '), char(9), ' ')
FROM memory_fts
JOIN memory_index ON memory_fts.rowid = memory_index.rowid
WHERE memory_fts MATCH ?1",
    );
    if !args.include_archived {
        sql.push_str(" AND memory_index.status <> 'archived'");
    }
    sql.push_str(
        "
ORDER BY bm25(memory_fts, 8.0, 4.0, 2.0, 1.0)
LIMIT ?2",
    );

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params![args.query, args.limit as i64], |row| {
        Ok(SearchResult {
            path: row.get(0)?,
            title: row.get(1)?,
            status: row.get(2)?,
            rank: row.get(3)?,
            snippet: row.get(4)?,
        })
    })?;

    let mut results = Vec::new();
    for row in rows {
        results.push(row?);
    }

    if json {
        print!(
            "{{\"ok\":true,\"query\":\"{}\",\"results\":[",
            json_escape(&args.query)
        );
        for (idx, result) in results.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            print!(
                "{{\"path\":\"{}\",\"title\":\"{}\",\"status\":\"{}\",\"rank\":{},\"snippet\":\"{}\"}}",
                json_escape(&result.path),
                json_escape(&result.title),
                json_escape(&result.status),
                result.rank,
                json_escape(&result.snippet)
            );
        }
        println!("]}}");
    } else {
        for result in results {
            println!(
                "{}\t{}\t{}\t{}\t{}",
                result.path, result.title, result.status, result.rank, result.snippet
            );
        }
    }

    Ok(())
}

#[derive(Debug)]
struct SearchResult {
    path: String,
    title: String,
    status: String,
    rank: String,
    snippet: String,
}

fn index_full(conn: &mut Connection, vault: &Path) -> Result<usize> {
    let files = collect_markdown_files(vault)?;
    let mut seen = HashSet::new();
    let progress_every = progress_interval();
    let total = files.len();

    let tx = conn.transaction()?;
    let mut indexed = 0;
    for (idx, file) in files.iter().enumerate() {
        if let Some(rel) = rel_path(file, vault) {
            seen.insert(rel);
        }
        indexed += index_one(&tx, vault, file)?;
        if progress_every > 0 {
            let current = idx + 1;
            if current % progress_every == 0 || current == total {
                eprintln!("strata index: {current}/{total} files scanned, {indexed} indexed");
            }
        }
    }
    remove_stale(&tx, &seen)?;
    tx.commit()?;

    Ok(indexed)
}

fn progress_interval() -> usize {
    if let Ok(value) = env::var("STRATA_INDEX_PROGRESS_EVERY") {
        return value.parse::<usize>().unwrap_or(0);
    }

    if std::io::stderr().is_terminal() {
        100
    } else {
        0
    }
}

fn collect_markdown_files(vault: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    for rel in ["0_core/doc", "1_draft", "2_knowledge", "3_intelligence"] {
        let root = vault.join(rel);
        if root.is_dir() {
            collect_markdown_files_rec(&root, &mut files)?;
        }
    }
    files.sort();
    Ok(files)
}

fn collect_markdown_files_rec(dir: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            collect_markdown_files_rec(&path, files)?;
        } else if file_type.is_file() && path.extension().and_then(|ext| ext.to_str()) == Some("md")
        {
            files.push(path);
        }
    }
    Ok(())
}

fn index_one(tx: &Transaction<'_>, vault: &Path, file: &Path) -> Result<usize> {
    if !file.is_file() || file.extension().and_then(|ext| ext.to_str()) != Some("md") {
        return Ok(0);
    }

    let abs = absolute_path(file)?;
    let Some(rel) = rel_path(&abs, vault) else {
        return Ok(0);
    };
    let Some(strata) = detect_strata(&rel) else {
        return Ok(0);
    };
    if is_excluded_path(&rel) {
        return Ok(0);
    }

    let content = fs::read_to_string(&abs)?;
    let frontmatter = parse_frontmatter(&content);
    let doc = build_document(&abs, &rel, strata, &content, &frontmatter)?;
    let links = extract_links(&content);
    let sections = extract_sections(&content);

    delete_path(tx, &rel)?;
    tx.execute(
        "INSERT INTO memory_index (id,path,title,description,strata,status,tags,sources,source_note,version,last_edit_summary,created,modified,content,content_hash,metadata) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
        params![
            doc.id,
            doc.path,
            doc.title,
            doc.description,
            doc.strata,
            doc.status,
            doc.tags,
            doc.sources,
            doc.source_note,
            doc.version,
            doc.last_edit_summary,
            doc.created,
            doc.modified,
            doc.content,
            doc.content_hash,
            "{}",
        ],
    )?;
    tx.execute(
        "INSERT INTO memory_fts(rowid,title,description,tags,content) SELECT rowid,title,description,tags,content FROM memory_index WHERE path = ?1",
        params![rel],
    )?;

    for link in links {
        tx.execute(
            "INSERT OR REPLACE INTO links (source_path,target,target_type,link_text,line,created_at) VALUES (?1,?2,?3,?4,?5,strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
            params![rel, link.target, link.target_type, link.text, link.line],
        )?;
    }

    for section in sections {
        tx.execute(
            "INSERT OR REPLACE INTO sections (path,heading,level,start_line,end_line,content) VALUES (?1,?2,?3,?4,?5,?6)",
            params![rel, section.heading, section.level, section.start_line, section.end_line, section.content],
        )?;
    }

    Ok(1)
}

fn build_document(
    abs: &Path,
    rel: &str,
    strata: &str,
    content: &str,
    frontmatter: &Frontmatter,
) -> Result<Document> {
    let status = frontmatter.scalar("status").unwrap_or_else(|| {
        if rel.starts_with("3_intelligence/report/") {
            "generated".to_string()
        } else {
            default_status(strata, rel).to_string()
        }
    });
    if !valid_status(&status) {
        return Err(format!("invalid status for {rel}: {status}").into());
    }

    let id = frontmatter
        .scalar("id")
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| make_id(rel));
    let title = frontmatter
        .scalar("title")
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            abs.file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or("untitled")
                .replace('-', " ")
        });
    let version = frontmatter
        .scalar("version")
        .and_then(|value| value.parse::<i64>().ok())
        .unwrap_or(1);
    let bytes = fs::read(abs)?;

    Ok(Document {
        id,
        path: rel.to_string(),
        title,
        description: frontmatter.scalar("description").unwrap_or_default(),
        strata: strata.to_string(),
        status,
        tags: json_array(&frontmatter.array("tags")),
        sources: json_array(&frontmatter.array("sources")),
        source_note: frontmatter.scalar("source_note").unwrap_or_default(),
        version,
        last_edit_summary: frontmatter.scalar("last_edit_summary").unwrap_or_default(),
        created: frontmatter.scalar("created").unwrap_or_default(),
        modified: frontmatter.scalar("modified").unwrap_or_default(),
        content: content.to_string(),
        content_hash: posix_cksum_hash(&bytes),
    })
}

fn delete_path(tx: &Transaction<'_>, rel: &str) -> Result<()> {
    tx.execute(
        "DELETE FROM memory_fts WHERE rowid IN (SELECT rowid FROM memory_index WHERE path = ?1)",
        params![rel],
    )?;
    tx.execute("DELETE FROM memory_index WHERE path = ?1", params![rel])?;
    tx.execute("DELETE FROM links WHERE source_path = ?1", params![rel])?;
    tx.execute("DELETE FROM sections WHERE path = ?1", params![rel])?;
    Ok(())
}

fn remove_stale(tx: &Transaction<'_>, seen: &HashSet<String>) -> Result<()> {
    let existing = {
        let mut stmt = tx.prepare("SELECT path FROM memory_index")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut existing = Vec::new();
        for row in rows {
            existing.push(row?);
        }
        existing
    };

    for path in existing {
        if !seen.contains(&path) {
            delete_path(tx, &path)?;
        }
    }

    Ok(())
}

#[derive(Default, Debug)]
struct Frontmatter {
    scalars: HashMap<String, String>,
    arrays: HashMap<String, Vec<String>>,
}

impl Frontmatter {
    fn scalar(&self, key: &str) -> Option<String> {
        self.scalars.get(key).cloned()
    }

    fn array(&self, key: &str) -> Vec<String> {
        self.arrays.get(key).cloned().unwrap_or_default()
    }
}

fn parse_frontmatter(content: &str) -> Frontmatter {
    let mut fm = Frontmatter::default();
    let mut lines = content.lines();
    if lines.next() != Some("---") {
        return fm;
    }

    let mut current_array: Option<String> = None;
    for line in lines {
        if line == "---" {
            break;
        }

        if let Some(key) = current_array.clone() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Some(value) = trimmed.strip_prefix("- ") {
                fm.arrays
                    .entry(key)
                    .or_default()
                    .push(unquote(value.trim()));
                continue;
            }
            current_array = None;
        }

        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim().to_string();
        let value = value.trim();
        if value.is_empty() {
            fm.arrays.entry(key.clone()).or_default();
            current_array = Some(key);
        } else {
            fm.scalars.insert(key, unquote(value));
        }
    }

    fm
}

fn unquote(value: &str) -> String {
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        value[1..value.len() - 1].to_string()
    } else {
        value.to_string()
    }
}

fn json_array(values: &[String]) -> String {
    let body = values
        .iter()
        .map(|value| format!("\"{}\"", json_escape(value)))
        .collect::<Vec<_>>()
        .join(",");
    format!("[{body}]")
}

fn json_escape(value: &str) -> String {
    let mut out = String::new();
    for ch in value.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            other => out.push(other),
        }
    }
    out
}

fn extract_links(content: &str) -> Vec<Link> {
    let mut links = Vec::new();
    for (line_idx, line) in content.lines().enumerate() {
        let mut rest = line;
        while let Some(open_text) = rest.find('[') {
            rest = &rest[open_text + 1..];
            let Some(close_text) = rest.find("](") else {
                continue;
            };
            let text = &rest[..close_text];
            rest = &rest[close_text + 2..];
            let Some(close_target) = rest.find(')') else {
                break;
            };
            let target = &rest[..close_target];
            rest = &rest[close_target + 1..];
            let target_type = if target.starts_with("http://") || target.starts_with("https://") {
                "url"
            } else if target.starts_with("[[") {
                "unresolved"
            } else {
                "local"
            };
            links.push(Link {
                target: target.to_string(),
                target_type: target_type.to_string(),
                text: text.to_string(),
                line: (line_idx + 1) as i64,
            });
        }
    }
    links
}

fn extract_sections(content: &str) -> Vec<Section> {
    let lines: Vec<&str> = content.lines().collect();
    let mut sections = Vec::new();
    let mut current: Option<(String, i64, usize, String)> = None;

    for (idx, line) in lines.iter().enumerate() {
        if let Some((level, heading)) = parse_heading(line) {
            if let Some((prev_heading, prev_level, start, prev_content)) = current.take() {
                sections.push(Section {
                    heading: prev_heading,
                    level: prev_level,
                    start_line: start as i64,
                    end_line: idx as i64,
                    content: prev_content,
                });
            }
            current = Some((heading, level, idx + 1, format!("{line}\n")));
        } else if let Some((_, _, _, current_content)) = current.as_mut() {
            current_content.push_str(line);
            current_content.push('\n');
        }
    }

    if let Some((heading, level, start, section_content)) = current {
        sections.push(Section {
            heading,
            level,
            start_line: start as i64,
            end_line: lines.len() as i64,
            content: section_content,
        });
    }

    sections
}

fn parse_heading(line: &str) -> Option<(i64, String)> {
    let hashes = line.chars().take_while(|ch| *ch == '#').count();
    if !(1..=6).contains(&hashes) {
        return None;
    }
    let rest = &line[hashes..];
    if !rest.starts_with(' ') && !rest.starts_with('\t') {
        return None;
    }
    Some((hashes as i64, rest.trim().to_string()))
}

fn absolute_path(path: &Path) -> Result<PathBuf> {
    if path.is_absolute() {
        Ok(path.to_path_buf())
    } else {
        Ok(env::current_dir()?.join(path))
    }
}

fn rel_path(path: &Path, vault: &Path) -> Option<String> {
    let rel = path.strip_prefix(vault).ok()?;
    Some(rel.to_string_lossy().trim_start_matches('/').to_string())
}

fn detect_strata(rel: &str) -> Option<&'static str> {
    match rel {
        path if path.starts_with("0_core/") => Some("0_core"),
        path if path.starts_with("1_draft/") => Some("1_draft"),
        path if path.starts_with("2_knowledge/") => Some("2_knowledge"),
        path if path.starts_with("3_intelligence/") => Some("3_intelligence"),
        _ => None,
    }
}

fn is_excluded_path(rel: &str) -> bool {
    rel.starts_with("0_core/cache/")
        || rel.starts_with("0_core/tmp/")
        || rel.starts_with("0_core/test/tmp/")
        || rel.starts_with("0_core/db/")
}

fn default_status(strata: &str, rel: &str) -> &'static str {
    if rel.contains("/_archived/") || rel.contains("_archived/") {
        return "archived";
    }

    match strata {
        "0_core" => "core",
        "1_draft" => "pending",
        "2_knowledge" | "3_intelligence" => "verified",
        _ => "pending",
    }
}

fn valid_status(status: &str) -> bool {
    matches!(
        status,
        "pending" | "verified" | "archived" | "generated" | "core"
    )
}

fn make_id(rel: &str) -> String {
    let stamp = unix_timestamp();
    let crc = posix_cksum(rel.as_bytes());
    format!("mem_{stamp}_{crc}")
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn posix_cksum_hash(bytes: &[u8]) -> String {
    format!("{}:{}", posix_cksum(bytes), bytes.len())
}

fn posix_cksum(bytes: &[u8]) -> u32 {
    let mut crc: u32 = 0;
    for byte in bytes {
        crc = (crc << 8) ^ POSIX_CRC_TABLE[((crc >> 24) as u8 ^ byte) as usize];
    }

    let mut len = bytes.len();
    while len != 0 {
        let byte = (len & 0xff) as u8;
        crc = (crc << 8) ^ POSIX_CRC_TABLE[((crc >> 24) as u8 ^ byte) as usize];
        len >>= 8;
    }
    !crc
}

const POSIX_CRC_TABLE: [u32; 256] = [
    0x00000000, 0x04c11db7, 0x09823b6e, 0x0d4326d9, 0x130476dc, 0x17c56b6b, 0x1a864db2, 0x1e475005,
    0x2608edb8, 0x22c9f00f, 0x2f8ad6d6, 0x2b4bcb61, 0x350c9b64, 0x31cd86d3, 0x3c8ea00a, 0x384fbdbd,
    0x4c11db70, 0x48d0c6c7, 0x4593e01e, 0x4152fda9, 0x5f15adac, 0x5bd4b01b, 0x569796c2, 0x52568b75,
    0x6a1936c8, 0x6ed82b7f, 0x639b0da6, 0x675a1011, 0x791d4014, 0x7ddc5da3, 0x709f7b7a, 0x745e66cd,
    0x9823b6e0, 0x9ce2ab57, 0x91a18d8e, 0x95609039, 0x8b27c03c, 0x8fe6dd8b, 0x82a5fb52, 0x8664e6e5,
    0xbe2b5b58, 0xbaea46ef, 0xb7a96036, 0xb3687d81, 0xad2f2d84, 0xa9ee3033, 0xa4ad16ea, 0xa06c0b5d,
    0xd4326d90, 0xd0f37027, 0xddb056fe, 0xd9714b49, 0xc7361b4c, 0xc3f706fb, 0xceb42022, 0xca753d95,
    0xf23a8028, 0xf6fb9d9f, 0xfbb8bb46, 0xff79a6f1, 0xe13ef6f4, 0xe5ffeb43, 0xe8bccd9a, 0xec7dd02d,
    0x34867077, 0x30476dc0, 0x3d044b19, 0x39c556ae, 0x278206ab, 0x23431b1c, 0x2e003dc5, 0x2ac12072,
    0x128e9dcf, 0x164f8078, 0x1b0ca6a1, 0x1fcdbb16, 0x018aeb13, 0x054bf6a4, 0x0808d07d, 0x0cc9cdca,
    0x7897ab07, 0x7c56b6b0, 0x71159069, 0x75d48dde, 0x6b93dddb, 0x6f52c06c, 0x6211e6b5, 0x66d0fb02,
    0x5e9f46bf, 0x5a5e5b08, 0x571d7dd1, 0x53dc6066, 0x4d9b3063, 0x495a2dd4, 0x44190b0d, 0x40d816ba,
    0xaca5c697, 0xa864db20, 0xa527fdf9, 0xa1e6e04e, 0xbfa1b04b, 0xbb60adfc, 0xb6238b25, 0xb2e29692,
    0x8aad2b2f, 0x8e6c3698, 0x832f1041, 0x87ee0df6, 0x99a95df3, 0x9d684044, 0x902b669d, 0x94ea7b2a,
    0xe0b41de7, 0xe4750050, 0xe9362689, 0xedf73b3e, 0xf3b06b3b, 0xf771768c, 0xfa325055, 0xfef34de2,
    0xc6bcf05f, 0xc27dede8, 0xcf3ecb31, 0xcbffd686, 0xd5b88683, 0xd1799b34, 0xdc3abded, 0xd8fba05a,
    0x690ce0ee, 0x6dcdfd59, 0x608edb80, 0x644fc637, 0x7a089632, 0x7ec98b85, 0x738aad5c, 0x774bb0eb,
    0x4f040d56, 0x4bc510e1, 0x46863638, 0x42472b8f, 0x5c007b8a, 0x58c1663d, 0x558240e4, 0x51435d53,
    0x251d3b9e, 0x21dc2629, 0x2c9f00f0, 0x285e1d47, 0x36194d42, 0x32d850f5, 0x3f9b762c, 0x3b5a6b9b,
    0x0315d626, 0x07d4cb91, 0x0a97ed48, 0x0e56f0ff, 0x1011a0fa, 0x14d0bd4d, 0x19939b94, 0x1d528623,
    0xf12f560e, 0xf5ee4bb9, 0xf8ad6d60, 0xfc6c70d7, 0xe22b20d2, 0xe6ea3d65, 0xeba91bbc, 0xef68060b,
    0xd727bbb6, 0xd3e6a601, 0xdea580d8, 0xda649d6f, 0xc423cd6a, 0xc0e2d0dd, 0xcda1f604, 0xc960ebb3,
    0xbd3e8d7e, 0xb9ff90c9, 0xb4bcb610, 0xb07daba7, 0xae3afba2, 0xaafbe615, 0xa7b8c0cc, 0xa379dd7b,
    0x9b3660c6, 0x9ff77d71, 0x92b45ba8, 0x9675461f, 0x8832161a, 0x8cf30bad, 0x81b02d74, 0x857130c3,
    0x5d8a9099, 0x594b8d2e, 0x5408abf7, 0x50c9b640, 0x4e8ee645, 0x4a4ffbf2, 0x470cdd2b, 0x43cdc09c,
    0x7b827d21, 0x7f436096, 0x7200464f, 0x76c15bf8, 0x68860bfd, 0x6c47164a, 0x61043093, 0x65c52d24,
    0x119b4be9, 0x155a565e, 0x18197087, 0x1cd86d30, 0x029f3d35, 0x065e2082, 0x0b1d065b, 0x0fdc1bec,
    0x3793a651, 0x3352bbe6, 0x3e119d3f, 0x3ad08088, 0x2497d08d, 0x2056cd3a, 0x2d15ebe3, 0x29d4f654,
    0xc5a92679, 0xc1683bce, 0xcc2b1d17, 0xc8ea00a0, 0xd6ad50a5, 0xd26c4d12, 0xdf2f6bcb, 0xdbee767c,
    0xe3a1cbc1, 0xe760d676, 0xea23f0af, 0xeee2ed18, 0xf0a5bd1d, 0xf464a0aa, 0xf9278673, 0xfde69bc4,
    0x89b8fd09, 0x8d79e0be, 0x803ac667, 0x84fbdbd0, 0x9abc8bd5, 0x9e7d9662, 0x933eb0bb, 0x97ffad0c,
    0xafb010b1, 0xab710d06, 0xa6322bdf, 0xa2f33668, 0xbcb4666d, 0xb8757bda, 0xb5365d03, 0xb1f740b4,
];
