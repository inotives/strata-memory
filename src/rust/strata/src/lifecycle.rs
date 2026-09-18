use crate::index::model::{collect_markdown_files as collect_index_markdown_files, read_document};
use crate::index::posix_cksum;
use crate::{absolute_path, json_escape, rel_path, Result};
use chrono::Utc;
use std::fs;
use std::path::Path;

pub(crate) struct NormalizeSummary {
    pub(crate) path: String,
    pub(crate) strata: String,
    pub(crate) status: String,
}

pub(crate) struct PromoteSummary {
    pub(crate) target: String,
    pub(crate) log: String,
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
    let approved_by = parsed.scalar("approved_by");
    let modified_by = parsed.scalar("modified_by");
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
    if let Some(approved_by) = approved_by.as_deref().filter(|value| !value.is_empty()) {
        push_quoted(&mut output, "approved_by", approved_by);
    }
    if let Some(modified_by) = modified_by.as_deref().filter(|value| !value.is_empty()) {
        push_quoted(&mut output, "modified_by", modified_by);
    }
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

pub(crate) fn promote(
    vault: &Path,
    source: &Path,
    to: &str,
    new_slug: Option<&str>,
    approved_by: &str,
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
    let target_abs = vault.join(&target_rel);
    if target_abs.exists() {
        return Err(format!("target exists; use --new-slug: {target_rel}").into());
    }

    let promoted_id = parsed.scalar("id").unwrap_or_else(|| make_id(&target_rel));
    reject_duplicate_document_id(vault, &promoted_id, &source_rel)?;

    let now = Utc::now();
    let promoted = build_promote_candidate(
        &parsed,
        &source_abs,
        &description,
        target_strata,
        "verified",
        &target_rel,
        approved_by,
        now,
    )?;
    validate_candidate(
        &promoted,
        target_strata,
        "promoted candidate failed normalization",
    )?;
    fs::create_dir_all(target_abs.parent().ok_or("invalid target path")?)?;
    fs::create_dir_all(vault.join("3_intelligence/report/operation"))?;
    fs::write(&target_abs, promoted)?;
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
    });
    fs::write(&log_abs, serde_json::to_string(&log)?)?;

    Ok(PromoteSummary {
        target: log["target"].as_str().unwrap_or_default().to_string(),
        log: log_rel,
    })
}

fn reject_duplicate_document_id(vault: &Path, id: &str, source_rel: &str) -> Result<()> {
    for file in collect_index_markdown_files(vault)? {
        let Some(indexed) = read_document(vault, &file)? else {
            continue;
        };
        let document = indexed.document;
        if document.path != source_rel && document.id == id {
            return Err(format!("document ID already exists: {id} at {}", document.path).into());
        }
    }
    Ok(())
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
    approved_by: &str,
    now: chrono::DateTime<Utc>,
) -> Result<String> {
    let id = parsed.scalar("id").unwrap_or_else(|| make_id(rel_for_id));
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
        push_block_or_key(&mut output, sources.as_deref(), "sources");
        if let Some(source_note) = source_note.as_deref().filter(|value| !value.is_empty()) {
            push_quoted(&mut output, "source_note", source_note);
        } else {
            push_quoted(&mut output, "source_note", "Promoted from draft.");
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
    push_quoted(&mut output, "approved_by", approved_by);
    push_quoted(&mut output, "modified_by", approved_by);
    push_quoted(
        &mut output,
        "modified",
        &Utc::now().format("%Y-%m-%d").to_string(),
    );
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

fn default_status(strata: &str, _rel: &str) -> &'static str {
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
