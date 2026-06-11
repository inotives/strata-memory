use crate::{absolute_path, config, json_escape, posix_cksum, rel_path, Result};
use chrono::{DateTime, Utc};
use serde::Serialize;
use std::fs;
use std::path::Path;

pub(crate) struct NormalizeSummary {
    pub(crate) path: String,
    pub(crate) strata: String,
    pub(crate) status: String,
}

pub(crate) struct RetentionSummary {
    pub(crate) report: String,
    pub(crate) mode: String,
    pub(crate) candidate_count: usize,
    pub(crate) deleted_count: usize,
    pub(crate) kept_count: usize,
    pub(crate) skipped_count: usize,
}

pub(crate) struct PromoteSummary {
    pub(crate) target: String,
    pub(crate) archive: String,
    pub(crate) log: String,
}

#[derive(Serialize)]
struct RetentionReport {
    ok: bool,
    generated_at: String,
    mode: String,
    retention_days: i64,
    candidate_count: usize,
    deleted_count: usize,
    kept_count: usize,
    skipped_count: usize,
    records: Vec<RetentionRecord>,
}

#[derive(Serialize)]
struct RetentionRecord {
    action: String,
    path: String,
    archived_at: String,
    age_days: Option<i64>,
    reason: String,
}

pub(crate) fn normalize(vault: &Path, target: &Path, check: bool) -> Result<NormalizeSummary> {
    if !target.is_file() {
        return Err(format!("target not found: {}", target.to_string_lossy()).into());
    }

    let abs = absolute_path(target)?;
    let Some(rel) = rel_path(&abs, vault) else {
        return Err(format!("target is outside a Strata tier: {}", abs.to_string_lossy()).into());
    };
    let Some(strata) = detect_strata(&rel) else {
        return Err(format!("target is outside a Strata tier: {rel}").into());
    };

    let content = fs::read_to_string(&abs)?;
    let parsed = ParsedMarkdown::parse(&content);
    let today = Utc::now().format("%Y-%m-%d").to_string();

    let status = parsed
        .scalar("status")
        .unwrap_or_else(|| default_status(strata, &rel).to_string());
    let id = parsed.scalar("id").unwrap_or_else(|| make_id(&rel));
    let title = parsed
        .scalar("title")
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            abs.file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or("untitled")
                .replace('-', " ")
        });
    let description = parsed.scalar("description").unwrap_or_default();
    let sources = parsed.array_block("sources");
    let tags = parsed.array_block("tags");
    let source_note = parsed.scalar("source_note");
    let last_edit_summary = parsed.scalar("last_edit_summary");
    let promoted_at = parsed.scalar("promoted_at");
    let version = parsed.scalar("version").unwrap_or_else(|| "1".to_string());
    let created = parsed.scalar("created").unwrap_or_else(|| today.clone());
    let modified = today;

    if matches!(strata, "2_knowledge" | "3_intelligence") && description.is_empty() {
        return Err(format!("description is required for durable tier: {rel}").into());
    }

    let mut output = String::new();
    output.push_str("---\n");
    push_quoted(&mut output, "id", &id);
    push_quoted(&mut output, "title", &title);
    push_quoted(&mut output, "description", &description);
    push_quoted(&mut output, "strata", strata);
    push_quoted(&mut output, "status", &status);
    push_block_or_key(&mut output, tags.as_deref(), "tags");
    if matches!(strata, "2_knowledge" | "3_intelligence") {
        push_block_or_key(&mut output, sources.as_deref(), "sources");
        if let Some(source_note) = source_note.as_deref().filter(|value| !value.is_empty()) {
            push_quoted(&mut output, "source_note", source_note);
        }
    } else if let Some(sources) = sources {
        output.push_str(&sources);
        if !sources.ends_with('\n') {
            output.push('\n');
        }
    }
    output.push_str(&format!("version: {version}\n"));
    if let Some(summary) = last_edit_summary
        .as_deref()
        .filter(|value| !value.is_empty())
    {
        push_quoted(&mut output, "last_edit_summary", summary);
    }
    push_quoted(&mut output, "created", &created);
    push_quoted(&mut output, "modified", &modified);
    if let Some(promoted_at) = promoted_at.as_deref().filter(|value| !value.is_empty()) {
        push_quoted(&mut output, "promoted_at", promoted_at);
    }
    output.push_str("---\n");
    output.push_str(&parsed.body);

    if !check {
        write_atomic(vault, &abs, &output)?;
    }

    Ok(NormalizeSummary {
        path: rel,
        strata: strata.to_string(),
        status,
    })
}

pub(crate) fn retention(vault: &Path, apply: bool) -> Result<RetentionSummary> {
    let days = config::retention_archived_drafts_days(vault)?;
    let archive_root = vault.join("1_draft/_archived");
    let report_dir = vault.join("3_intelligence/report/maintenance");
    fs::create_dir_all(&report_dir)?;
    fs::create_dir_all(vault.join("0_core/tmp"))?;

    let now = Utc::now();
    let mut records = Vec::new();
    if archive_root.is_dir() {
        let mut files = Vec::new();
        collect_markdown_files(&archive_root, &mut files)?;
        files.sort();
        for file in files {
            let abs = absolute_path(&file)?;
            let rel = rel_path(&abs, vault).unwrap_or_else(|| abs.to_string_lossy().to_string());
            let content = fs::read_to_string(&abs)?;
            let parsed = ParsedMarkdown::parse(&content);
            let archived_at = parsed.scalar("archived_at").unwrap_or_default();
            if archived_at.is_empty() {
                records.push(retention_record(
                    "skipped",
                    rel,
                    "",
                    None,
                    "missing_archived_at",
                ));
                continue;
            }

            let Ok(archived_at_time) = DateTime::parse_from_rfc3339(&archived_at) else {
                records.push(retention_record(
                    "skipped",
                    rel,
                    &archived_at,
                    None,
                    "invalid_archived_at",
                ));
                continue;
            };
            let age_days = (now.timestamp() - archived_at_time.timestamp()) / 86_400;
            if age_days < days {
                records.push(retention_record(
                    "kept",
                    rel,
                    &archived_at,
                    Some(age_days),
                    "within_retention",
                ));
                continue;
            }

            if apply {
                fs::remove_file(&abs)?;
                records.push(retention_record(
                    "deleted",
                    rel,
                    &archived_at,
                    Some(age_days),
                    "expired",
                ));
            } else {
                records.push(retention_record(
                    "candidate",
                    rel,
                    &archived_at,
                    Some(age_days),
                    "expired",
                ));
            }
        }
    }

    let candidate_count = count_action(&records, "candidate");
    let deleted_count = count_action(&records, "deleted");
    let kept_count = count_action(&records, "kept");
    let skipped_count = count_action(&records, "skipped");
    let mode = if apply { "apply" } else { "report" }.to_string();
    let generated_at = now.format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let today = now.format("%Y-%m-%d").to_string();
    let report_abs = report_dir.join(format!("retention-{today}.json"));
    let report = RetentionReport {
        ok: true,
        generated_at,
        mode: mode.clone(),
        retention_days: days,
        candidate_count,
        deleted_count,
        kept_count,
        skipped_count,
        records,
    };
    fs::write(&report_abs, serde_json::to_string_pretty(&report)?)?;
    let report_rel =
        rel_path(&report_abs, vault).unwrap_or_else(|| report_abs.to_string_lossy().to_string());

    Ok(RetentionSummary {
        report: report_rel,
        mode,
        candidate_count,
        deleted_count,
        kept_count,
        skipped_count,
    })
}

pub(crate) fn promote(
    vault: &Path,
    source: &Path,
    to: &str,
    new_slug: Option<&str>,
) -> Result<PromoteSummary> {
    if !source.is_file() {
        return Err(format!("source not found: {}", source.to_string_lossy()).into());
    }

    let source_abs = absolute_path(source)?;
    let Some(source_rel) = rel_path(&source_abs, vault) else {
        return Err(format!(
            "source must be under 1_draft: {}",
            source_abs.to_string_lossy()
        )
        .into());
    };
    if !source_rel.starts_with("1_draft/") {
        return Err(format!("source must be under 1_draft: {source_rel}").into());
    }
    let draft_subpath = source_rel.trim_start_matches("1_draft/");
    if draft_subpath.starts_with("_archived/") {
        return Err(format!("archived drafts cannot be promoted: {source_rel}").into());
    }

    let content = fs::read_to_string(&source_abs)?;
    let parsed = ParsedMarkdown::parse(&content);
    let description = parsed.scalar("description").unwrap_or_default();
    if description.is_empty() {
        return Err(format!("description is required before promotion: {source_rel}").into());
    }
    let status = parsed.scalar("status").unwrap_or_default();
    if !status.is_empty() && status != "pending" {
        return Err(format!("only pending drafts can be promoted: {source_rel}").into());
    }

    let draft_path = Path::new(draft_subpath);
    let draft_dir = draft_path
        .parent()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_else(|| ".".to_string());
    let mut draft_base = draft_path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or("invalid draft filename")?
        .to_string();
    if let Some(slug) = new_slug {
        validate_new_slug(slug)?;
        draft_base = if slug.ends_with(".md") {
            slug.to_string()
        } else {
            format!("{slug}.md")
        };
    }

    let target_room = promote_target_room(to, &draft_dir)?;
    let target_strata = target_room
        .split('/')
        .next()
        .ok_or("invalid promotion target")?;
    let target_rel = format!("{target_room}/{draft_base}");
    let archive_rel = format!("1_draft/_archived/{draft_subpath}");
    let target_abs = vault.join(&target_rel);
    let archive_abs = vault.join(&archive_rel);
    if target_abs.exists() {
        return Err(format!("target exists; use --new-slug: {target_rel}").into());
    }
    if archive_abs.exists() {
        return Err(format!("archive target exists: {archive_rel}").into());
    }

    let now = Utc::now();
    let promoted = build_promote_candidate(
        &parsed,
        &source_abs,
        &description,
        target_strata,
        "verified",
        &target_rel,
        &archive_rel,
        None,
        now,
    )?;
    let archived = build_promote_candidate(
        &parsed,
        &source_abs,
        &description,
        "1_draft",
        "archived",
        &archive_rel,
        &archive_rel,
        Some(&source_rel),
        now,
    )?;

    validate_candidate(
        &promoted,
        target_strata,
        "promoted candidate failed normalization",
    )?;
    validate_candidate(
        &archived,
        "1_draft",
        "archived candidate failed normalization",
    )?;

    fs::create_dir_all(target_abs.parent().ok_or("invalid target path")?)?;
    fs::create_dir_all(archive_abs.parent().ok_or("invalid archive path")?)?;
    fs::create_dir_all(vault.join("3_intelligence/report/operation"))?;
    fs::write(&target_abs, promoted)?;
    fs::write(&archive_abs, archived)?;
    fs::remove_file(&source_abs)?;

    let log_rel = format!(
        "3_intelligence/report/operation/promote-{}.json",
        now.format("%Y%m%d-%H%M%S")
    );
    let log_abs = vault.join(&log_rel);
    let log = serde_json::json!({
        "ok": true,
        "source": source_rel,
        "target": target_rel,
        "archive": archive_rel,
    });
    fs::write(&log_abs, serde_json::to_string(&log)?)?;

    Ok(PromoteSummary {
        target: log["target"].as_str().unwrap_or_default().to_string(),
        archive: log["archive"].as_str().unwrap_or_default().to_string(),
        log: log_rel,
    })
}

fn promote_target_room(to: &str, draft_dir: &str) -> Result<String> {
    let to = to.trim_matches('/');
    if to.is_empty()
        || to.starts_with('/')
        || to.contains('\\')
        || to
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == ".." || part.starts_with('.'))
    {
        return Err("--to must be a safe path under 2_knowledge or 3_intelligence".into());
    }

    if to == "2_knowledge" || to == "3_intelligence" {
        Ok(format!("{to}/{draft_dir}"))
    } else if to.starts_with("2_knowledge/") || to.starts_with("3_intelligence/") {
        Ok(to.to_string())
    } else {
        Err("--to must be 2_knowledge, 3_intelligence, or a room under them".into())
    }
}

fn validate_new_slug(slug: &str) -> Result<()> {
    if slug.is_empty()
        || !slug.chars().all(|ch| {
            ch.is_ascii_lowercase() || ch.is_ascii_digit() || matches!(ch, '.' | '_' | '-')
        })
    {
        return Err(
            "--new-slug must use lowercase letters, numbers, dot, underscore, or dash".into(),
        );
    }
    Ok(())
}

fn build_promote_candidate(
    parsed: &ParsedMarkdown,
    source_abs: &Path,
    description: &str,
    strata: &str,
    status: &str,
    rel_for_id: &str,
    archive_rel: &str,
    archived_from: Option<&str>,
    now: chrono::DateTime<Utc>,
) -> Result<String> {
    let mut id = parsed.scalar("id").unwrap_or_else(|| make_id(rel_for_id));
    if archived_from.is_some() {
        id.push_str("_archived");
    }
    let title = parsed
        .scalar("title")
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            Path::new(rel_for_id)
                .file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or("untitled")
                .replace('-', " ")
        });
    let tags = parsed.array_block("tags");
    let sources = parsed.array_block("sources");
    let source_note = parsed.scalar("source_note");
    let version = parsed.scalar("version").unwrap_or_else(|| "1".to_string());
    let created = parsed
        .scalar("created")
        .unwrap_or_else(|| Utc::now().format("%Y-%m-%d").to_string());
    let last_edit_summary = parsed.scalar("last_edit_summary");
    let now_rfc3339 = now.format("%Y-%m-%dT%H:%M:%SZ").to_string();

    let mut output = String::new();
    output.push_str("---\n");
    push_quoted(&mut output, "id", &id);
    push_quoted(&mut output, "title", &title);
    push_quoted(&mut output, "description", description);
    push_quoted(&mut output, "strata", strata);
    push_quoted(&mut output, "status", status);
    push_block_or_key(&mut output, tags.as_deref(), "tags");
    if matches!(strata, "2_knowledge" | "3_intelligence") {
        output.push_str("sources:\n");
        output.push_str(&format!("  - \"{}\"\n", yaml_quote_escape(archive_rel)));
        if let Some(source_note) = source_note.as_deref().filter(|value| !value.is_empty()) {
            push_quoted(&mut output, "source_note", source_note);
        } else {
            push_quoted(&mut output, "source_note", "Promoted from archived draft.");
        }
        push_quoted(&mut output, "promoted_at", &now_rfc3339);
    } else if let Some(sources) = sources {
        output.push_str(&sources);
        if !sources.ends_with('\n') {
            output.push('\n');
        }
    }
    output.push_str(&format!("version: {version}\n"));
    if let Some(summary) = last_edit_summary
        .as_deref()
        .filter(|value| !value.is_empty())
    {
        push_quoted(&mut output, "last_edit_summary", summary);
    }
    push_quoted(&mut output, "created", &created);
    push_quoted(
        &mut output,
        "modified",
        &Utc::now().format("%Y-%m-%d").to_string(),
    );
    if let Some(archived_from) = archived_from {
        push_quoted(&mut output, "archived_at", &now_rfc3339);
        push_quoted(
            &mut output,
            "archived_reason",
            &format!("Promoted to {rel_for_id}."),
        );
        push_quoted(&mut output, "archived_from", archived_from);
    }
    output.push_str("---\n");
    output.push_str(&parsed.body);

    if !source_abs.is_file() {
        return Err("source disappeared during promotion".into());
    }
    Ok(output)
}

fn validate_candidate(content: &str, strata: &str, message: &str) -> Result<()> {
    let parsed = ParsedMarkdown::parse(content);
    if matches!(strata, "2_knowledge" | "3_intelligence")
        && parsed.scalar("description").unwrap_or_default().is_empty()
    {
        return Err(message.to_string().into());
    }
    Ok(())
}

fn retention_record(
    action: &str,
    path: String,
    archived_at: &str,
    age_days: Option<i64>,
    reason: &str,
) -> RetentionRecord {
    RetentionRecord {
        action: action.to_string(),
        path,
        archived_at: archived_at.to_string(),
        age_days,
        reason: reason.to_string(),
    }
}

fn count_action(records: &[RetentionRecord], action: &str) -> usize {
    records
        .iter()
        .filter(|record| record.action == action)
        .count()
}

fn collect_markdown_files(dir: &Path, files: &mut Vec<std::path::PathBuf>) -> Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            collect_markdown_files(&path, files)?;
        } else if file_type.is_file() && path.extension().and_then(|ext| ext.to_str()) == Some("md")
        {
            files.push(path);
        }
    }
    Ok(())
}

struct ParsedMarkdown {
    frontmatter: Vec<String>,
    body: String,
}

impl ParsedMarkdown {
    fn parse(content: &str) -> Self {
        let mut lines = content.lines();
        if lines.next() != Some("---") {
            return Self {
                frontmatter: Vec::new(),
                body: content.to_string(),
            };
        }

        let mut frontmatter = Vec::new();
        let mut body = String::new();
        let mut in_frontmatter = true;
        for line in lines {
            if in_frontmatter && line == "---" {
                in_frontmatter = false;
                continue;
            }
            if in_frontmatter {
                frontmatter.push(line.to_string());
            } else {
                body.push_str(line);
                body.push('\n');
            }
        }

        Self { frontmatter, body }
    }

    fn scalar(&self, key: &str) -> Option<String> {
        let prefix = format!("{key}:");
        self.frontmatter.iter().find_map(|line| {
            if line.starts_with(&prefix) {
                let value = line[prefix.len()..].trim();
                Some(unquote(value))
            } else {
                None
            }
        })
    }

    fn array_block(&self, key: &str) -> Option<String> {
        let prefix = format!("{key}:");
        let mut out = Vec::new();
        let mut found = false;
        for line in &self.frontmatter {
            if !found && line.starts_with(&prefix) {
                found = true;
                out.push(line.clone());
                continue;
            }
            if found {
                let trimmed = line.trim();
                if line.starts_with("  -") || line.starts_with('\t') || trimmed.is_empty() {
                    out.push(line.clone());
                    continue;
                }
                break;
            }
        }
        found.then(|| {
            let mut block = out.join("\n");
            block.push('\n');
            block
        })
    }
}

fn push_quoted(output: &mut String, key: &str, value: &str) {
    output.push_str(&format!("{key}: \"{}\"\n", yaml_quote_escape(value)));
}

fn push_block_or_key(output: &mut String, block: Option<&str>, key: &str) {
    if let Some(block) = block.filter(|block| !block.trim().is_empty()) {
        output.push_str(block);
        if !block.ends_with('\n') {
            output.push('\n');
        }
    } else {
        output.push_str(key);
        output.push_str(":\n");
    }
}

fn write_atomic(vault: &Path, target: &Path, content: &str) -> Result<()> {
    let tmp_root = vault.join("0_core/tmp");
    fs::create_dir_all(&tmp_root)?;
    let tmp = tmp_root.join(format!("normalize-{}", std::process::id()));
    fs::write(&tmp, content)?;
    fs::rename(tmp, target)?;
    Ok(())
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

fn make_id(rel: &str) -> String {
    let stamp = Utc::now().format("%Y%m%d_%H%M%S");
    let crc = posix_cksum(rel.as_bytes());
    format!("mem_{stamp}_{crc}")
}

fn unquote(value: &str) -> String {
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        value[1..value.len() - 1].to_string()
    } else {
        value.to_string()
    }
}

fn yaml_quote_escape(value: &str) -> String {
    json_escape(value).replace("\\/", "/")
}
