use crate::Result;
use rusqlite::{params, Connection, OptionalExtension};
use std::fs;
use std::path::Path;

pub(crate) fn migrate(vault: &Path) -> Result<usize> {
    let db_path = vault.join("0_core/db/strata.db");
    if let Some(parent) = db_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let conn = Connection::open(db_path)?;
    let schema = fs::read_to_string(vault.join("0_core/db/schema.sql"))?;
    conn.execute_batch(&schema)?;

    let migrations_dir = vault.join("0_core/db/migrations");
    let mut migrations = Vec::new();
    if migrations_dir.is_dir() {
        for entry in fs::read_dir(migrations_dir)? {
            let entry = entry?;
            if entry.file_type()?.is_file()
                && entry.path().extension().and_then(|ext| ext.to_str()) == Some("sql")
            {
                migrations.push(entry.path());
            }
        }
    }
    migrations.sort();

    let mut applied_count = 0;
    for migration in migrations {
        let Some(name) = migration.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        let Some(version) = name.split('_').next() else {
            continue;
        };

        let applied: Option<String> = conn
            .query_row(
                "SELECT version FROM schema_migrations WHERE version = ?1 LIMIT 1",
                params![version],
                |row| row.get(0),
            )
            .optional()?;
        if applied.is_some() {
            continue;
        }

        let sql = fs::read_to_string(&migration)?;
        conn.execute_batch(&sql)?;
        conn.execute(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (?1, strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
            params![version],
        )?;
        applied_count += 1;
    }

    Ok(applied_count)
}
