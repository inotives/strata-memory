// ponytail: indexing stays internal until Turso search is complete; remove this allow when dispatch is enabled.
#![allow(dead_code)]

use crate::cli::IndexMode;
use crate::index::model::{collect_markdown_files, read_document};
use crate::rel_path;
use crate::Result;
use std::collections::HashSet;
use std::env;
use std::fs;
use std::future::Future;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use tokio::runtime::Builder as RuntimeBuilder;
use turso::{Builder, Connection};

pub(super) fn database_path(vault: &Path) -> PathBuf {
    vault.join("0_core/db/strata-turso.db")
}

pub(super) fn migrate(vault: &Path) -> Result<usize> {
    block_on(async {
        let db_path = database_path(vault);
        if let Some(parent) = db_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let db = Builder::new_local(
            db_path
                .to_str()
                .ok_or("Turso database path must be valid UTF-8")?,
        )
        .build()
        .await?;
        let conn = db.connect()?;
        let schema = fs::read_to_string(vault.join("0_core/db/turso/schema.sql"))?;
        conn.execute_batch(schema).await?;

        let migrations_dir = vault.join("0_core/db/turso/migrations");
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
            let mut rows = conn
                .query(
                    "SELECT version FROM schema_migrations WHERE version = ?1 LIMIT 1",
                    [version],
                )
                .await?;
            if rows.next().await?.is_some() {
                continue;
            }

            conn.execute_batch(fs::read_to_string(&migration)?).await?;
            conn.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (?1, datetime('now'))",
                [version],
            )
            .await?;
            applied_count += 1;
        }

        Ok(applied_count)
    })
}

pub(super) fn refresh(vault: &Path, mode: IndexMode) -> Result<usize> {
    migrate(vault)?;
    block_on(async {
        let db_path = database_path(vault);
        let db = Builder::new_local(
            db_path
                .to_str()
                .ok_or("Turso database path must be valid UTF-8")?,
        )
        .build()
        .await?;
        let conn = db.connect()?;
        conn.execute("BEGIN IMMEDIATE", ()).await?;

        let result = match mode {
            IndexMode::Full => index_full(&conn, vault).await,
            IndexMode::Target(target) => index_one(&conn, vault, &target).await,
        };

        match result {
            Ok(indexed) => {
                conn.execute("COMMIT", ()).await?;
                Ok(indexed)
            }
            Err(err) => {
                let _ = conn.execute("ROLLBACK", ()).await;
                Err(err)
            }
        }
    })
}

async fn index_full(conn: &Connection, vault: &Path) -> Result<usize> {
    let files = collect_markdown_files(vault)?;
    let seen: HashSet<String> = files
        .iter()
        .filter_map(|file| rel_path(file, vault))
        .collect();
    let progress_every = progress_interval();
    let total = files.len();

    remove_stale(conn, &seen).await?;
    let mut indexed = 0;
    for (idx, file) in files.iter().enumerate() {
        indexed += index_one(conn, vault, file).await?;
        if progress_every > 0 {
            let current = idx + 1;
            if current % progress_every == 0 || current == total {
                eprintln!("strata index: {current}/{total} files scanned, {indexed} indexed");
            }
        }
    }
    remove_stale(conn, &seen).await?;
    Ok(indexed)
}

async fn index_one(conn: &Connection, vault: &Path, file: &Path) -> Result<usize> {
    let Some(indexed) = read_document(vault, file)? else {
        return Ok(0);
    };
    let doc = indexed.document;
    let rel = doc.path.clone();

    delete_path(conn, &rel).await?;
    conn.execute(
        "INSERT INTO memory_index (id,path,title,description,strata,status,tags,sources,source_note,version,last_edit_summary,created,modified,content,content_hash,metadata) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
        (
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
        ),
    )
    .await?;

    for link in indexed.links {
        conn.execute(
            "INSERT OR REPLACE INTO links (source_path,target,target_type,link_text,line,created_at) VALUES (?1,?2,?3,?4,?5,datetime('now'))",
            (
                rel.as_str(),
                link.target,
                link.target_type,
                link.text,
                link.line,
            ),
        )
        .await?;
    }

    for section in indexed.sections {
        conn.execute(
            "INSERT OR REPLACE INTO sections (path,heading,level,start_line,end_line,content) VALUES (?1,?2,?3,?4,?5,?6)",
            (
                rel.as_str(),
                section.heading,
                section.level,
                section.start_line,
                section.end_line,
                section.content,
            ),
        )
        .await?;
    }

    Ok(1)
}

async fn delete_path(conn: &Connection, rel: &str) -> Result<()> {
    conn.execute("DELETE FROM memory_index WHERE path = ?1", [rel])
        .await?;
    conn.execute("DELETE FROM links WHERE source_path = ?1", [rel])
        .await?;
    conn.execute("DELETE FROM sections WHERE path = ?1", [rel])
        .await?;
    Ok(())
}

async fn remove_stale(conn: &Connection, seen: &HashSet<String>) -> Result<()> {
    let mut rows = conn.query("SELECT path FROM memory_index", ()).await?;
    let mut existing = Vec::new();
    while let Some(row) = rows.next().await? {
        existing.push(row.get::<String>(0)?);
    }

    for path in existing {
        if !seen.contains(&path) {
            delete_path(conn, &path).await?;
        }
    }
    Ok(())
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

fn block_on<T>(future: impl Future<Output = Result<T>>) -> Result<T> {
    RuntimeBuilder::new_current_thread()
        .build()?
        .block_on(future)
}

pub(super) fn unavailable<T>() -> Result<T> {
    Err(
        "index backend turso is not available yet; set index.backend: sqlite and run strata refresh"
            .into(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn full_and_target_indexing_preserve_contract() -> Result<()> {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let vault = env::temp_dir().join(format!("strata-turso-index-{stamp}"));
        let db_dir = vault.join("0_core/db/turso/migrations");
        let knowledge = vault.join("2_knowledge/concept");
        fs::create_dir_all(&db_dir)?;
        fs::create_dir_all(&knowledge)?;
        fs::write(
            vault.join("0_core/db/turso/schema.sql"),
            include_str!("../../../../db/turso/schema.sql"),
        )?;
        fs::write(
            db_dir.join("001_init.sql"),
            include_str!("../../../../db/turso/migrations/001_init.sql"),
        )?;
        fs::write(
            db_dir.join("002_semantic_foundation.sql"),
            include_str!("../../../../db/turso/migrations/002_semantic_foundation.sql"),
        )?;

        let alpha = knowledge.join("alpha.md");
        let beta = knowledge.join("beta.md");
        fs::write(
            &alpha,
            "---\ntitle: Alpha\ndescription: First concept\nstatus: verified\n---\n# Alpha\n\n[Beta](beta.md)\n",
        )?;
        fs::write(
            &beta,
            "---\ntitle: Beta\ndescription: Second concept\nstatus: verified\n---\n# Beta\n",
        )?;

        assert_eq!(refresh(&vault, IndexMode::Full)?, 2);
        assert_eq!(counts(&vault)?, (2, 1, 2));

        fs::write(
            &alpha,
            "---\ntitle: Alpha Updated\ndescription: First concept\nstatus: verified\n---\n# Alpha Updated\n",
        )?;
        assert_eq!(refresh(&vault, IndexMode::Target(alpha))?, 1);
        assert_eq!(
            title(&vault, "2_knowledge/concept/alpha.md")?,
            "Alpha Updated"
        );

        fs::remove_file(beta)?;
        assert_eq!(refresh(&vault, IndexMode::Full)?, 1);
        assert_eq!(counts(&vault)?.0, 1);

        fs::remove_dir_all(vault)?;
        Ok(())
    }

    fn counts(vault: &Path) -> Result<(i64, i64, i64)> {
        block_on(async {
            let db = open(vault).await?;
            let conn = db.connect()?;
            Ok((
                count(&conn, "memory_index").await?,
                count(&conn, "links").await?,
                count(&conn, "sections").await?,
            ))
        })
    }

    fn title(vault: &Path, path: &str) -> Result<String> {
        block_on(async {
            let db = open(vault).await?;
            let conn = db.connect()?;
            let mut rows = conn
                .query("SELECT title FROM memory_index WHERE path = ?1", [path])
                .await?;
            let row = rows.next().await?.ok_or("missing indexed document")?;
            Ok(row.get(0)?)
        })
    }

    async fn count(conn: &Connection, table: &str) -> Result<i64> {
        let mut rows = conn
            .query(format!("SELECT count(*) FROM {table}"), ())
            .await?;
        let row = rows.next().await?.ok_or("missing count row")?;
        Ok(row.get(0)?)
    }

    async fn open(vault: &Path) -> Result<turso::Database> {
        let path = database_path(vault);
        Ok(
            Builder::new_local(path.to_str().ok_or("invalid test path")?)
                .build()
                .await?,
        )
    }
}
