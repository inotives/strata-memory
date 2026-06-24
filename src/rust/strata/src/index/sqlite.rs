use crate::cli::{IndexMode, SearchArgs};
use crate::index;
use crate::index::model::{
    collect_markdown_files, posix_cksum_hash, read_document, IndexBackend, SemanticRefreshSummary,
};
use crate::{config, json_escape, rel_path, Result};
use rusqlite::{params, Connection, OptionalExtension, Transaction};
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};

pub(super) fn database_path(vault: &Path) -> PathBuf {
    vault.join("0_core/db/strata.db")
}

pub(super) fn migrate(vault: &Path) -> Result<usize> {
    let db_path = database_path(vault);
    if let Some(parent) = db_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let conn = Connection::open(db_path)?;
    let schema = fs::read_to_string(vault.join("0_core/db/sqlite/schema.sql"))?;
    conn.execute_batch(&schema)?;

    let migrations_dir = vault.join("0_core/db/sqlite/migrations");
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

pub(super) fn refresh(vault: &Path, mode: IndexMode) -> Result<usize> {
    let active = index::migrate(vault)?;
    let mut conn = Connection::open(active.db_path)?;

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

pub(super) fn search(vault: &Path, args: &SearchArgs, json: bool) -> Result<()> {
    let indexed = if args.refresh {
        Some(refresh(vault, IndexMode::Full)?)
    } else {
        None
    };

    let db_path = index::active(vault)?.db_path;
    if !db_path.is_file() {
        return Err("database not found; run strata refresh first".into());
    }

    let conn = Connection::open(db_path)?;
    let requested_mode = if args.hybrid { "hybrid" } else { "fts" };
    let mut warnings = Vec::new();
    if args.hybrid && semantic_search_available(vault, &conn)? {
        return search_hybrid(vault, &conn, args, json, indexed);
    }

    let mode = "fts";
    if args.hybrid {
        let warning = "semantic search unavailable; returned FTS5 results".to_string();
        if !json {
            eprintln!("strata search: warning: {warning}");
        }
        warnings.push(warning);
    }

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
        if json {
            print!(
                "{{\"ok\":true,\"backend\":\"sqlite\",\"query\":\"{}\",\"refreshed\":{},\"requested_mode\":\"{}\",\"mode\":\"{}\",\"warnings\":",
                json_escape(&args.query),
                args.refresh,
                requested_mode,
                mode
            );
            print_json_string_array(&warnings);
            print!(",");
            if let Some(indexed) = indexed {
                print!("\"indexed\":{indexed},");
            }
            print!("\"results\":[");
            for (idx, row) in rows.enumerate() {
                if idx > 0 {
                    print!(",");
                }
                print!("\"{}\"", json_escape(&row?));
            }
            println!("]}}");
            return Ok(());
        }
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
            "{{\"ok\":true,\"backend\":\"sqlite\",\"query\":\"{}\",\"refreshed\":{},\"requested_mode\":\"{}\",\"mode\":\"{}\",\"warnings\":",
            json_escape(&args.query),
            args.refresh,
            requested_mode,
            mode
        );
        print_json_string_array(&warnings);
        print!(",");
        if let Some(indexed) = indexed {
            print!("\"indexed\":{indexed},");
        }
        print!("\"results\":[");
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

pub(super) fn semantic_status(vault: &Path, json: bool) -> Result<()> {
    let active = index::migrate(vault)?;
    let semantic = config::semantic(vault)?;
    let provider_configured =
        !semantic.provider.is_empty() && !semantic.model.is_empty() && semantic.embedding_dim > 0;
    let runtime_available = builtin_embedding_supported(&semantic);
    let conn = Connection::open(active.db_path)?;
    let embedding_count = table_row_count(&conn, "semantic_embeddings")?;
    let model_count = table_row_count(&conn, "semantic_models")?;
    let vector_index_ready = embedding_count > 0;
    let vector_extension_available = false;
    let semantic_available = provider_configured && runtime_available && vector_index_ready;
    let fallback = "fts5";

    if json {
        println!(
            "{{\"ok\":true,\"backend\":\"sqlite\",\"semantic_available\":{},\"provider_configured\":{},\"runtime_available\":{},\"vector_index_ready\":{},\"vector_extension_available\":{},\"fallback\":\"{}\",\"provider\":\"{}\",\"model\":\"{}\",\"embedding_dim\":{},\"embedding_count\":{},\"model_count\":{}}}",
            semantic_available,
            provider_configured,
            runtime_available,
            vector_index_ready,
            vector_extension_available,
            fallback,
            json_escape(&semantic.provider),
            json_escape(&semantic.model),
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
        println!("Fallback: FTS5");
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

#[derive(Debug)]
struct SemanticCandidate {
    path: String,
    title: String,
    status: String,
    target_type: String,
    section_start_line: Option<i64>,
    text: String,
    score: f32,
}

pub(super) fn semantic_refresh(vault: &Path) -> Result<SemanticRefreshSummary> {
    let active = index::migrate(vault)?;
    let semantic = config::semantic(vault)?;
    validate_builtin_embedding_config(&semantic)?;

    let mut conn = Connection::open(active.db_path)?;
    let tx = conn.transaction()?;
    tx.execute(
        "INSERT OR REPLACE INTO semantic_models (provider,model,embedding_dim,configured_at) VALUES (?1,?2,?3,strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
        params![semantic.provider, semantic.model, semantic.embedding_dim],
    )?;
    tx.execute(
        "DELETE FROM semantic_embeddings WHERE provider = ?1 AND model = ?2",
        params![semantic.provider, semantic.model],
    )?;

    let mut descriptions = 0;
    let mut sections = 0;
    {
        let mut stmt = tx.prepare(
            "SELECT path, description
FROM memory_index
WHERE trim(ifnull(description,'')) <> ''",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (path, description) = row?;
            insert_embedding(
                &tx,
                &semantic,
                &path,
                "description",
                None,
                description.trim(),
            )?;
            descriptions += 1;
        }
    }

    {
        let mut stmt = tx.prepare(
            "SELECT path, start_line, content
FROM sections
WHERE trim(ifnull(content,'')) <> ''",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?;
        for row in rows {
            let (path, start_line, content) = row?;
            insert_embedding(&tx, &semantic, &path, "section", Some(start_line), &content)?;
            sections += 1;
        }
    }

    tx.commit()?;

    Ok(SemanticRefreshSummary {
        backend: IndexBackend::Sqlite,
        provider: semantic.provider,
        model: semantic.model,
        embedding_dim: semantic.embedding_dim,
        indexed: descriptions + sections,
        descriptions,
        sections,
    })
}

fn search_hybrid(
    vault: &Path,
    conn: &Connection,
    args: &SearchArgs,
    json: bool,
    indexed: Option<usize>,
) -> Result<()> {
    let semantic = config::semantic(vault)?;
    let query_vector = embed_text(&args.query, semantic.embedding_dim as usize);
    let fts_results = load_fts_results(conn, args, args.limit.saturating_mul(4).max(50))?;
    let mut merged: HashMap<String, SearchResult> = HashMap::new();
    let mut scores: HashMap<String, f32> = HashMap::new();

    for (idx, result) in fts_results.into_iter().enumerate() {
        let fts_score = 1.0 / ((idx + 1) as f32);
        scores.insert(result.path.clone(), fts_score * 0.65);
        merged.insert(result.path.clone(), result);
    }

    for candidate in load_semantic_candidates(conn, &semantic, args, &query_vector)? {
        let vector_score = candidate.score.max(0.0) * 0.35;
        let score = scores.entry(candidate.path.clone()).or_insert(0.0);
        if vector_score > *score {
            *score = vector_score;
        } else {
            *score += vector_score;
        }
        let snippet = semantic_snippet(&candidate);
        merged
            .entry(candidate.path.clone())
            .or_insert_with(|| SearchResult {
                path: candidate.path,
                title: candidate.title,
                status: candidate.status,
                rank: String::new(),
                snippet,
            });
    }

    let mut results = merged.into_values().collect::<Vec<_>>();
    results.sort_by(|left, right| {
        let left_score = scores.get(&left.path).copied().unwrap_or_default();
        let right_score = scores.get(&right.path).copied().unwrap_or_default();
        right_score
            .partial_cmp(&left_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left.path.cmp(&right.path))
    });
    results.truncate(args.limit);
    for result in &mut results {
        let score = scores.get(&result.path).copied().unwrap_or_default();
        result.rank = format!("{score:.6}");
    }

    if args.paths_only {
        if json {
            print_search_json_header(&args.query, args.refresh, "hybrid", "hybrid", &[], indexed);
            print!("\"results\":[");
            for (idx, result) in results.iter().enumerate() {
                if idx > 0 {
                    print!(",");
                }
                print!("\"{}\"", json_escape(&result.path));
            }
            println!("]}}");
        } else {
            for result in results {
                println!("{}", result.path);
            }
        }
        return Ok(());
    }

    if json {
        print_search_json_header(&args.query, args.refresh, "hybrid", "hybrid", &[], indexed);
        print!("\"results\":[");
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

fn print_search_json_header(
    query: &str,
    refreshed: bool,
    requested_mode: &str,
    mode: &str,
    warnings: &[String],
    indexed: Option<usize>,
) {
    print!(
        "{{\"ok\":true,\"backend\":\"sqlite\",\"query\":\"{}\",\"refreshed\":{},\"requested_mode\":\"{}\",\"mode\":\"{}\",\"warnings\":",
        json_escape(query),
        refreshed,
        requested_mode,
        mode
    );
    print_json_string_array(warnings);
    print!(",");
    if let Some(indexed) = indexed {
        print!("\"indexed\":{indexed},");
    }
}

fn semantic_search_available(vault: &Path, conn: &Connection) -> Result<bool> {
    let semantic = config::semantic(vault)?;
    if !builtin_embedding_supported(&semantic) {
        return Ok(false);
    }
    Ok(table_row_count(conn, "semantic_embeddings")? > 0)
}

fn builtin_embedding_supported(semantic: &config::Semantic) -> bool {
    semantic.provider == "builtin-hash" && semantic.model == "hash-v1" && semantic.embedding_dim > 0
}

fn validate_builtin_embedding_config(semantic: &config::Semantic) -> Result<()> {
    if semantic.provider.is_empty() && semantic.model.is_empty() && semantic.embedding_dim == 0 {
        return Err("semantic provider not configured; set provider builtin-hash, model hash-v1, and embedding_dim > 0".into());
    }
    if !builtin_embedding_supported(semantic) {
        return Err(format!(
            "unsupported semantic provider/model: {}/{}; supported local provider is builtin-hash/hash-v1",
            semantic.provider, semantic.model
        )
        .into());
    }
    Ok(())
}

fn insert_embedding(
    tx: &Transaction<'_>,
    semantic: &config::Semantic,
    path: &str,
    target_type: &str,
    section_start_line: Option<i64>,
    text: &str,
) -> Result<()> {
    let vector = embed_text(text, semantic.embedding_dim as usize);
    let vector_blob = encode_vector(&vector);
    let content_hash = posix_cksum_hash(text.as_bytes());
    tx.execute(
        "INSERT OR REPLACE INTO semantic_embeddings (path,target_type,section_start_line,content_hash,provider,model,embedding_dim,vector,updated_at) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
        params![
            path,
            target_type,
            section_start_line,
            content_hash,
            semantic.provider,
            semantic.model,
            semantic.embedding_dim,
            vector_blob,
        ],
    )?;
    Ok(())
}

fn load_fts_results(
    conn: &Connection,
    args: &SearchArgs,
    limit: usize,
) -> Result<Vec<SearchResult>> {
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
    let rows = stmt.query_map(params![args.query, limit as i64], |row| {
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
    Ok(results)
}

fn load_semantic_candidates(
    conn: &Connection,
    semantic: &config::Semantic,
    args: &SearchArgs,
    query_vector: &[f32],
) -> Result<Vec<SemanticCandidate>> {
    let mut sql = String::from(
        "SELECT semantic_embeddings.path,
       ifnull(memory_index.title,''),
       memory_index.status,
       semantic_embeddings.target_type,
       semantic_embeddings.section_start_line,
       CASE
         WHEN semantic_embeddings.target_type = 'description' THEN memory_index.description
         ELSE ifnull(sections.content, '')
       END,
       semantic_embeddings.vector
FROM semantic_embeddings
JOIN memory_index ON semantic_embeddings.path = memory_index.path
LEFT JOIN sections
  ON sections.path = semantic_embeddings.path
 AND sections.start_line = semantic_embeddings.section_start_line
WHERE semantic_embeddings.provider = ?1
  AND semantic_embeddings.model = ?2",
    );
    if !args.include_archived {
        sql.push_str(" AND memory_index.status <> 'archived'");
    }

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(params![semantic.provider, semantic.model], |row| {
        let blob: Vec<u8> = row.get(6)?;
        let vector = decode_vector(&blob);
        Ok(SemanticCandidate {
            path: row.get(0)?,
            title: row.get(1)?,
            status: row.get(2)?,
            target_type: row.get(3)?,
            section_start_line: row.get(4)?,
            text: row.get(5)?,
            score: cosine_similarity(query_vector, &vector),
        })
    })?;

    let mut best_by_path: HashMap<String, SemanticCandidate> = HashMap::new();
    for row in rows {
        let candidate = row?;
        let replace = best_by_path
            .get(&candidate.path)
            .map(|existing| candidate.score > existing.score)
            .unwrap_or(true);
        if replace {
            best_by_path.insert(candidate.path.clone(), candidate);
        }
    }
    let mut candidates = best_by_path.into_values().collect::<Vec<_>>();
    candidates.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left.path.cmp(&right.path))
    });
    candidates.truncate(args.limit.saturating_mul(4).max(50));
    Ok(candidates)
}

fn semantic_snippet(candidate: &SemanticCandidate) -> String {
    let mut text = candidate.text.replace(['\n', '\t'], " ");
    while text.contains("  ") {
        text = text.replace("  ", " ");
    }
    let trimmed = text.trim();
    let prefix = if candidate.target_type == "section" {
        match candidate.section_start_line {
            Some(line) => format!("section line {line}: "),
            None => "section: ".to_string(),
        }
    } else {
        "description: ".to_string()
    };
    let max_len = 140usize.saturating_sub(prefix.len());
    if trimmed.len() > max_len {
        format!(
            "{}{}...",
            prefix,
            &trimmed[..trimmed
                .char_indices()
                .take_while(|(idx, _)| *idx < max_len)
                .last()
                .map(|(idx, ch)| idx + ch.len_utf8())
                .unwrap_or(0)]
        )
    } else {
        format!("{prefix}{trimmed}")
    }
}

fn embed_text(text: &str, dim: usize) -> Vec<f32> {
    let dim = dim.max(1);
    let mut vector = vec![0.0f32; dim];
    for token in semantic_tokens(text) {
        let hash = fnv1a64(token.as_bytes());
        let idx = (hash as usize) % dim;
        vector[idx] += 1.0;
    }
    normalize_vector(&mut vector);
    vector
}

fn semantic_tokens(text: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    for ch in text.chars() {
        if ch.is_ascii_alphanumeric() {
            current.push(ch.to_ascii_lowercase());
        } else if !current.is_empty() {
            tokens.push(std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    tokens
}

fn normalize_vector(vector: &mut [f32]) {
    let magnitude = vector.iter().map(|value| value * value).sum::<f32>().sqrt();
    if magnitude <= f32::EPSILON {
        return;
    }
    for value in vector {
        *value /= magnitude;
    }
}

fn cosine_similarity(left: &[f32], right: &[f32]) -> f32 {
    left.iter()
        .zip(right.iter())
        .map(|(left, right)| left * right)
        .sum()
}

fn encode_vector(vector: &[f32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(vector.len() * 4);
    for value in vector {
        out.extend_from_slice(&value.to_le_bytes());
    }
    out
}

fn decode_vector(blob: &[u8]) -> Vec<f32> {
    blob.chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect()
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn index_full(conn: &mut Connection, vault: &Path) -> Result<usize> {
    let files = collect_markdown_files(vault)?;
    let seen: HashSet<String> = files
        .iter()
        .filter_map(|file| rel_path(file, vault))
        .collect();
    let progress_every = progress_interval();
    let total = files.len();

    let tx = conn.transaction()?;
    remove_stale(&tx, &seen)?;
    let mut indexed = 0;
    for (idx, file) in files.iter().enumerate() {
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

fn index_one(tx: &Transaction<'_>, vault: &Path, file: &Path) -> Result<usize> {
    let Some(indexed) = read_document(vault, file)? else {
        return Ok(0);
    };
    let doc = indexed.document;
    let rel = doc.path.clone();

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

    for link in indexed.links {
        tx.execute(
            "INSERT OR REPLACE INTO links (source_path,target,target_type,link_text,line,created_at) VALUES (?1,?2,?3,?4,?5,strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
            params![rel, link.target, link.target_type, link.text, link.line],
        )?;
    }

    for section in indexed.sections {
        tx.execute(
            "INSERT OR REPLACE INTO sections (path,heading,level,start_line,end_line,content) VALUES (?1,?2,?3,?4,?5,?6)",
            params![rel, section.heading, section.level, section.start_line, section.end_line, section.content],
        )?;
    }

    Ok(1)
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

fn print_json_string_array(values: &[String]) {
    print!("[");
    for (idx, value) in values.iter().enumerate() {
        if idx > 0 {
            print!(",");
        }
        print!("\"{}\"", json_escape(value));
    }
    print!("]");
}

fn table_row_count(conn: &Connection, table: &str) -> Result<i64> {
    let exists: i64 = conn.query_row(
        "SELECT count(*) FROM sqlite_master WHERE type IN ('table','virtual table') AND name = ?1",
        params![table],
        |row| row.get(0),
    )?;
    if exists == 0 {
        return Ok(0);
    }

    let sql = format!("SELECT count(*) FROM {table}");
    Ok(conn.query_row(&sql, [], |row| row.get(0))?)
}
