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
