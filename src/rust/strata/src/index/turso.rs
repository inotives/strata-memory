use crate::cli::{IndexMode, SearchArgs};
use crate::config;
use crate::index::model::{
    collect_markdown_files, embed_text, posix_cksum_hash, read_document,
    validate_builtin_embedding_config, IndexBackend, SearchResult, SemanticCandidate,
    SemanticRefreshSummary,
};
use crate::rel_path;
use crate::Result;
use std::collections::{HashMap, HashSet};
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
        .experimental_index_method(true)
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
        .experimental_index_method(true)
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

pub(super) fn search(vault: &Path, args: &SearchArgs, json: bool) -> Result<()> {
    let indexed = if args.refresh {
        Some(refresh(vault, IndexMode::Full)?)
    } else {
        None
    };
    if !database_path(vault).is_file() {
        return Err("database not found; run strata refresh first".into());
    }

    let semantic = config::semantic(vault)?;
    if args.hybrid && semantic_available(vault, &semantic)? {
        return search_hybrid(vault, &semantic, args, json, indexed);
    }

    let mut warnings = Vec::new();
    if args.hybrid {
        let warning = "semantic search unavailable; returned Turso FTS results".to_string();
        if !json {
            eprintln!("strata search: warning: {warning}");
        }
        warnings.push(warning);
    }
    let results = block_on(async {
        let db = open_database(vault).await?;
        let conn = db.connect()?;
        fts_results(&conn, &args.query, args.limit, args.include_archived).await
    })?;
    print_search_results(
        args,
        json,
        indexed,
        if args.hybrid { "hybrid" } else { "fts" },
        "fts",
        &warnings,
        &results,
    )
}

fn search_hybrid(
    vault: &Path,
    semantic: &config::Semantic,
    args: &SearchArgs,
    json: bool,
    indexed: Option<usize>,
) -> Result<()> {
    let fts = block_on(async {
        let db = open_database(vault).await?;
        let conn = db.connect()?;
        fts_results(
            &conn,
            &args.query,
            args.limit.saturating_mul(4).max(50),
            args.include_archived,
        )
        .await
    })?;
    let semantic_results = exact_semantic_candidates(
        vault,
        semantic,
        &args.query,
        args.limit.saturating_mul(4).max(50),
        args.include_archived,
    )?;

    let mut merged = HashMap::new();
    let mut scores = HashMap::new();
    for (idx, result) in fts.into_iter().enumerate() {
        scores.insert(result.path.clone(), 0.65 / ((idx + 1) as f32));
        merged.insert(result.path.clone(), result);
    }
    for candidate in semantic_results {
        let vector_score = candidate.score.max(0.0) * 0.35;
        *scores.entry(candidate.path.clone()).or_insert(0.0) += vector_score;
        let snippet = semantic_snippet(&candidate);
        merged
            .entry(candidate.path.clone())
            .or_insert(SearchResult {
                path: candidate.path,
                title: candidate.title,
                status: candidate.status,
                rank: String::new(),
                snippet,
            });
    }

    let mut ranked: Vec<_> = merged.into_values().collect();
    ranked.sort_by(|left, right| {
        scores
            .get(&right.path)
            .unwrap_or(&0.0)
            .total_cmp(scores.get(&left.path).unwrap_or(&0.0))
            .then_with(|| left.path.cmp(&right.path))
    });
    ranked.truncate(args.limit);
    for result in &mut ranked {
        result.rank = format!("{:.6}", scores.get(&result.path).unwrap_or(&0.0));
    }
    print_search_results(args, json, indexed, "hybrid", "hybrid", &[], &ranked)
}

fn print_search_results(
    args: &SearchArgs,
    json: bool,
    indexed: Option<usize>,
    requested_mode: &str,
    mode: &str,
    warnings: &[String],
    results: &[SearchResult],
) -> Result<()> {
    if json {
        print!(
            "{{\"ok\":true,\"backend\":\"turso\",\"query\":\"{}\",\"refreshed\":{},\"requested_mode\":\"{}\",\"mode\":\"{}\",\"warnings\":[",
            crate::json_escape(&args.query),
            args.refresh,
            requested_mode,
            mode
        );
        for (idx, warning) in warnings.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            print!("\"{}\"", crate::json_escape(warning));
        }
        print!("],");
        if let Some(indexed) = indexed {
            print!("\"indexed\":{indexed},");
        }
        print!("\"results\":[");
        for (idx, result) in results.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            if args.paths_only {
                print!("\"{}\"", crate::json_escape(&result.path));
            } else {
                print!(
                    "{{\"path\":\"{}\",\"title\":\"{}\",\"status\":\"{}\",\"rank\":{},\"snippet\":\"{}\"}}",
                    crate::json_escape(&result.path),
                    crate::json_escape(&result.title),
                    crate::json_escape(&result.status),
                    result.rank,
                    crate::json_escape(&result.snippet)
                );
            }
        }
        println!("]}}");
    } else {
        for result in results {
            if args.paths_only {
                println!("{}", result.path);
            } else {
                println!(
                    "{}\t{}\t{}\t{}\t{}",
                    result.path, result.title, result.status, result.rank, result.snippet
                );
            }
        }
    }
    Ok(())
}

pub(super) fn semantic_status(vault: &Path, json: bool) -> Result<()> {
    if !database_path(vault).is_file() {
        return Err("database not found; run strata refresh first".into());
    }
    let semantic = config::semantic(vault)?;
    let provider_configured =
        !semantic.provider.is_empty() && !semantic.model.is_empty() && semantic.embedding_dim > 0;
    let runtime_available = crate::index::model::builtin_embedding_supported(&semantic);
    let (embedding_count, model_count) = block_on(async {
        let db = open_database(vault).await?;
        let conn = db.connect()?;
        Ok((
            table_count(&conn, "semantic_embeddings").await?,
            table_count(&conn, "semantic_models").await?,
        ))
    })?;
    let vector_index_ready = embedding_count > 0;
    let semantic_available = provider_configured && runtime_available && vector_index_ready;

    if json {
        println!(
            "{{\"ok\":true,\"backend\":\"turso\",\"experimental\":true,\"semantic_available\":{},\"provider_configured\":{},\"runtime_available\":{},\"vector_index_ready\":{},\"vector_extension_available\":true,\"fallback\":\"fts\",\"provider\":\"{}\",\"model\":\"{}\",\"embedding_dim\":{},\"embedding_count\":{},\"model_count\":{}}}",
            semantic_available,
            provider_configured,
            runtime_available,
            vector_index_ready,
            crate::json_escape(&semantic.provider),
            crate::json_escape(&semantic.model),
            semantic.embedding_dim,
            embedding_count,
            model_count
        );
    } else {
        println!(
            "Semantic search: {}",
            if semantic_available {
                "available"
            } else {
                "unavailable"
            }
        );
        println!(
            "Provider configured: {}",
            if provider_configured { "yes" } else { "no" }
        );
        println!(
            "Runtime available: {}",
            if runtime_available { "yes" } else { "no" }
        );
        println!(
            "Vector index ready: {}",
            if vector_index_ready { "yes" } else { "no" }
        );
        println!("Fallback: Turso FTS");
    }
    Ok(())
}

pub(super) fn migration_versions(vault: &Path) -> Result<Vec<String>> {
    block_on(async {
        let db = open_database(vault).await?;
        let conn = db.connect()?;
        let mut rows = conn
            .query("SELECT version FROM schema_migrations ORDER BY version", ())
            .await?;
        let mut versions = Vec::new();
        while let Some(row) = rows.next().await? {
            versions.push(row.get(0)?);
        }
        Ok(versions)
    })
}

pub(super) fn semantic_refresh(vault: &Path) -> Result<SemanticRefreshSummary> {
    let semantic = config::semantic(vault)?;
    semantic_refresh_with(vault, &semantic)
}

fn semantic_refresh_with(
    vault: &Path,
    semantic: &config::Semantic,
) -> Result<SemanticRefreshSummary> {
    validate_builtin_embedding_config(semantic)?;
    migrate(vault)?;
    block_on(async {
        let db = open_database(vault).await?;
        let conn = db.connect()?;
        conn.execute("BEGIN IMMEDIATE", ()).await?;
        let result = semantic_refresh_transaction(&conn, semantic).await;
        match result {
            Ok(summary) => {
                conn.execute("COMMIT", ()).await?;
                Ok(summary)
            }
            Err(err) => {
                let _ = conn.execute("ROLLBACK", ()).await;
                Err(err)
            }
        }
    })
}

async fn semantic_refresh_transaction(
    conn: &Connection,
    semantic: &config::Semantic,
) -> Result<SemanticRefreshSummary> {
    conn.execute(
        "INSERT OR REPLACE INTO semantic_models (provider,model,embedding_dim,configured_at) VALUES (?1,?2,?3,datetime('now'))",
        (
            semantic.provider.as_str(),
            semantic.model.as_str(),
            semantic.embedding_dim,
        ),
    )
    .await?;
    conn.execute(
        "DELETE FROM semantic_embeddings WHERE provider = ?1 AND model = ?2",
        (semantic.provider.as_str(), semantic.model.as_str()),
    )
    .await?;

    let mut description_rows = conn
        .query(
            "SELECT path, description FROM memory_index WHERE trim(ifnull(description,'')) <> ''",
            (),
        )
        .await?;
    let mut descriptions_to_index = Vec::new();
    while let Some(row) = description_rows.next().await? {
        descriptions_to_index.push((row.get::<String>(0)?, row.get::<String>(1)?));
    }

    let mut section_rows = conn
        .query(
            "SELECT path, start_line, content FROM sections WHERE trim(ifnull(content,'')) <> ''",
            (),
        )
        .await?;
    let mut sections_to_index = Vec::new();
    while let Some(row) = section_rows.next().await? {
        sections_to_index.push((
            row.get::<String>(0)?,
            row.get::<i64>(1)?,
            row.get::<String>(2)?,
        ));
    }

    for (path, description) in &descriptions_to_index {
        insert_embedding(
            conn,
            semantic,
            path,
            "description",
            None,
            description.trim(),
        )
        .await?;
    }
    for (path, start_line, content) in &sections_to_index {
        insert_embedding(conn, semantic, path, "section", Some(*start_line), content).await?;
    }

    let descriptions = descriptions_to_index.len();
    let sections = sections_to_index.len();
    Ok(SemanticRefreshSummary {
        backend: IndexBackend::Turso,
        provider: semantic.provider.clone(),
        model: semantic.model.clone(),
        embedding_dim: semantic.embedding_dim,
        indexed: descriptions + sections,
        descriptions,
        sections,
    })
}

async fn insert_embedding(
    conn: &Connection,
    semantic: &config::Semantic,
    path: &str,
    target_type: &str,
    section_start_line: Option<i64>,
    text: &str,
) -> Result<()> {
    let vector = embed_text(text, semantic.embedding_dim as usize);
    conn.execute(
        "INSERT OR REPLACE INTO semantic_embeddings (path,target_type,section_start_line,content_hash,provider,model,embedding_dim,vector,updated_at) VALUES (?1,?2,?3,?4,?5,?6,?7,vector32(?8),datetime('now'))",
        (
            path,
            target_type,
            section_start_line,
            posix_cksum_hash(text.as_bytes()),
            semantic.provider.as_str(),
            semantic.model.as_str(),
            semantic.embedding_dim,
            vector_text(&vector),
        ),
    )
    .await?;
    Ok(())
}

fn exact_semantic_candidates(
    vault: &Path,
    semantic: &config::Semantic,
    query: &str,
    limit: usize,
    include_archived: bool,
) -> Result<Vec<SemanticCandidate>> {
    let query_vector = vector_text(&embed_text(query, semantic.embedding_dim as usize));
    block_on(async {
        let db = open_database(vault).await?;
        let conn = db.connect()?;
        let archived_filter = if include_archived {
            ""
        } else {
            " AND memory_index.status <> 'archived'"
        };
        let sql = format!(
            "SELECT semantic_embeddings.path,
                    ifnull(memory_index.title,''),
                    memory_index.status,
                    semantic_embeddings.target_type,
                    semantic_embeddings.section_start_line,
                    CASE semantic_embeddings.target_type
                      WHEN 'description' THEN ifnull(memory_index.description,'')
                      ELSE ifnull(sections.content,'')
                    END,
                    1.0 - vector_distance_cos(semantic_embeddings.vector, vector32(?1))
             FROM semantic_embeddings
             JOIN memory_index ON memory_index.path = semantic_embeddings.path
             LEFT JOIN sections
               ON sections.path = semantic_embeddings.path
              AND sections.start_line = semantic_embeddings.section_start_line
             WHERE semantic_embeddings.provider = ?2
               AND semantic_embeddings.model = ?3{archived_filter}
             ORDER BY vector_distance_cos(semantic_embeddings.vector, vector32(?1))
             LIMIT ?4"
        );
        let mut rows = conn
            .query(
                sql,
                (
                    query_vector,
                    semantic.provider.as_str(),
                    semantic.model.as_str(),
                    limit as i64,
                ),
            )
            .await?;
        let mut candidates = Vec::new();
        while let Some(row) = rows.next().await? {
            candidates.push(SemanticCandidate {
                path: row.get(0)?,
                title: row.get(1)?,
                status: row.get(2)?,
                target_type: row.get(3)?,
                section_start_line: row.get(4)?,
                text: row.get(5)?,
                score: row.get::<f64>(6)? as f32,
            });
        }
        Ok(candidates)
    })
}

fn vector_text(vector: &[f32]) -> String {
    format!(
        "[{}]",
        vector
            .iter()
            .map(|value| value.to_string())
            .collect::<Vec<_>>()
            .join(",")
    )
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

async fn fts_results(
    conn: &Connection,
    query: &str,
    limit: usize,
    include_archived: bool,
) -> Result<Vec<SearchResult>> {
    let archived_filter = if include_archived {
        ""
    } else {
        " AND status <> 'archived'"
    };
    let sql = format!(
        "SELECT path, ifnull(title,''), status, ifnull(description,''), content
         FROM memory_index
         WHERE (title, description, tags, content) MATCH ?1{archived_filter}
         LIMIT ?2"
    );
    let mut rows = conn.query(sql, (query, limit as i64)).await?;
    let mut results = Vec::new();
    while let Some(row) = rows.next().await? {
        let description: String = row.get(3)?;
        let content: String = row.get(4)?;
        results.push(SearchResult {
            path: row.get(0)?,
            title: row.get(1)?,
            status: row.get(2)?,
            rank: results.len().to_string(),
            snippet: if description.is_empty() {
                content
                    .lines()
                    .find(|line| !line.trim().is_empty())
                    .unwrap_or("")
                    .to_string()
            } else {
                description
            },
        });
    }
    Ok(results)
}

fn semantic_available(vault: &Path, semantic: &config::Semantic) -> Result<bool> {
    if !crate::index::model::builtin_embedding_supported(semantic) {
        return Ok(false);
    }
    block_on(async {
        let db = open_database(vault).await?;
        let conn = db.connect()?;
        Ok(table_count(&conn, "semantic_embeddings").await? > 0)
    })
}

fn semantic_snippet(candidate: &SemanticCandidate) -> String {
    match candidate.target_type.as_str() {
        "section" => format!(
            "section line {}: {}",
            candidate.section_start_line.unwrap_or(0),
            candidate.text.replace('\n', " ")
        ),
        _ => candidate.text.replace('\n', " "),
    }
}

async fn table_count(conn: &Connection, table: &str) -> Result<i64> {
    let mut rows = conn
        .query(format!("SELECT count(*) FROM {table}"), ())
        .await?;
    let row = rows.next().await?.ok_or("missing count row")?;
    Ok(row.get(0)?)
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

async fn open_database(vault: &Path) -> Result<turso::Database> {
    let path = database_path(vault);
    Ok(Builder::new_local(
        path.to_str()
            .ok_or("Turso database path must be valid UTF-8")?,
    )
    .experimental_index_method(true)
    .build()
    .await?)
}

fn block_on<T>(future: impl Future<Output = Result<T>>) -> Result<T> {
    RuntimeBuilder::new_current_thread()
        .build()?
        .block_on(future)
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
        fs::write(
            db_dir.join("003_fts.sql"),
            include_str!("../../../../db/turso/migrations/003_fts.sql"),
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
        assert_eq!(
            fts_paths(&vault, "Alpha")?,
            vec!["2_knowledge/concept/alpha.md"]
        );
        let semantic = config::Semantic {
            provider: "builtin-hash".to_string(),
            model: "hash-v1".to_string(),
            embedding_dim: 64,
        };
        let semantic_summary = semantic_refresh_with(&vault, &semantic)?;
        assert_eq!(semantic_summary.descriptions, 2);
        assert_eq!(
            exact_semantic_candidates(&vault, &semantic, "First concept", 10, false)?[0].path,
            "2_knowledge/concept/alpha.md"
        );

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

    fn fts_paths(vault: &Path, query: &str) -> Result<Vec<String>> {
        block_on(async {
            let db = open(vault).await?;
            let conn = db.connect()?;
            Ok(fts_results(&conn, query, 10, false)
                .await?
                .into_iter()
                .map(|result| result.path)
                .collect())
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
                .experimental_index_method(true)
                .build()
                .await?,
        )
    }
}
