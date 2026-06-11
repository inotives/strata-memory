use crate::{absolute_path, collect_markdown_files_rec, config, json_escape, rel_path, Result};
use std::fs;
use std::path::{Path, PathBuf};

pub(crate) fn link_review(vault: &Path, json: bool) -> Result<()> {
    let issues = link_issues(vault)?;

    let error_count = issues
        .iter()
        .filter(|issue| issue.severity == "error")
        .count();

    if json {
        print!(
            "{{\"ok\":{},\"issue_count\":{},\"error_count\":{},\"issues\":[",
            if error_count == 0 { "true" } else { "false" },
            issues.len(),
            error_count
        );
        for (idx, issue) in issues.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            print!(
                "{{\"severity\":\"{}\",\"reason\":\"{}\",\"path\":\"{}\",\"target\":\"{}\",\"line\":{}}}",
                json_escape(&issue.severity),
                json_escape(&issue.reason),
                json_escape(&issue.path),
                json_escape(&issue.target),
                issue.line
            );
        }
        println!("]}}");
    } else if issues.is_empty() {
        println!("No link issues found");
    } else {
        println!("Link issues:");
        for issue in &issues {
            println!(
                "{} {} {}:{} -> {}",
                issue.severity, issue.reason, issue.path, issue.line, issue.target
            );
        }
    }

    if error_count > 0 {
        return Err("link review found durable link errors".into());
    }

    Ok(())
}

pub(crate) fn link_review_counts(vault: &Path) -> Result<(usize, usize)> {
    let issues = link_issues(vault)?;
    let error_count = issues
        .iter()
        .filter(|issue| issue.severity == "error")
        .count();
    Ok((issues.len(), error_count))
}

pub(crate) fn privacy_review(vault: &Path, json: bool) -> Result<()> {
    let files = collect_privacy_review_files(vault)?;
    let mut warnings = Vec::new();

    for file in files {
        let abs = absolute_path(&file)?;
        let Some(rel) = rel_path(&abs, vault) else {
            continue;
        };
        let content = fs::read_to_string(&abs)?;
        warnings.extend(privacy_warnings_for_file(&rel, &content));
    }

    if json {
        print!(
            "{{\"ok\":true,\"warning_count\":{},\"warnings\":[",
            warnings.len()
        );
        for (idx, warning) in warnings.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            print!(
                "{{\"severity\":\"warn\",\"reason\":\"{}\",\"path\":\"{}\",\"line\":{},\"detail\":\"{}\"}}",
                json_escape(&warning.reason),
                json_escape(&warning.path),
                warning.line,
                json_escape(&warning.detail)
            );
        }
        println!("]}}");
    } else if warnings.is_empty() {
        println!("No private-data warnings found");
    } else {
        println!("Private-data warnings:");
        for warning in &warnings {
            println!(
                "warn {} {}:{} {}",
                warning.reason, warning.path, warning.line, warning.detail
            );
        }
    }

    Ok(())
}

pub(crate) fn tag_review(vault: &Path, json: bool) -> Result<()> {
    let unknown = unknown_tags(vault)?;

    if json {
        print!(
            "{{\"ok\":true,\"unknown_count\":{},\"unknown\":[",
            unknown.len()
        );
        for (idx, item) in unknown.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            print!(
                "{{\"path\":\"{}\",\"tag\":\"{}\",\"similar\":\"{}\"}}",
                json_escape(&item.path),
                json_escape(&item.tag),
                json_escape(&item.similar)
            );
        }
        println!("]}}");
    } else if unknown.is_empty() {
        println!("No unknown tags found");
    } else {
        println!("Unknown tags:");
        for item in &unknown {
            if item.similar.is_empty() {
                println!("{}: {}", item.path, item.tag);
            } else {
                println!("{}: {} (similar: {})", item.path, item.tag, item.similar);
            }
        }
    }

    Ok(())
}

pub(crate) fn unknown_tag_count(vault: &Path) -> Result<usize> {
    Ok(unknown_tags(vault)?.len())
}

pub(crate) fn room_review(vault: &Path, json: bool) -> Result<()> {
    let unregistered = unregistered_rooms(vault)?;

    if json {
        print!(
            "{{\"ok\":true,\"unregistered_count\":{},\"unregistered\":[",
            unregistered.len()
        );
        for (idx, item) in unregistered.iter().enumerate() {
            if idx > 0 {
                print!(",");
            }
            print!(
                "{{\"path\":\"{}\",\"room\":\"{}\"}}",
                json_escape(&item.path),
                json_escape(&item.room)
            );
        }
        println!("]}}");
    } else if unregistered.is_empty() {
        println!("No unregistered rooms found");
    } else {
        println!("Unregistered rooms:");
        for item in &unregistered {
            println!("{}: {}", item.path, item.room);
        }
    }

    Ok(())
}

pub(crate) fn unregistered_room_count(vault: &Path) -> Result<usize> {
    Ok(unregistered_rooms(vault)?.len())
}

fn collect_review_markdown_files(vault: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    for rel in ["1_draft", "2_knowledge", "3_intelligence"] {
        let root = vault.join(rel);
        if root.is_dir() {
            collect_markdown_files_rec(&root, &mut files)?;
        }
    }
    files.sort();
    Ok(files)
}

fn collect_privacy_review_files(vault: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    for rel in ["1_draft", "2_knowledge", "3_intelligence"] {
        let root = vault.join(rel);
        if root.is_dir() {
            collect_privacy_review_files_rec(&root, &mut files)?;
        }
    }

    let agents = vault.join("AGENTS.md");
    if agents.is_file() {
        files.push(agents);
    }

    files.sort();
    Ok(files)
}

fn collect_privacy_review_files_rec(root: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_privacy_review_files_rec(&path, files)?;
        } else if is_privacy_review_file(&path) {
            files.push(path);
        }
    }
    Ok(())
}

fn is_privacy_review_file(path: &Path) -> bool {
    let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
        return false;
    };
    if name == ".env" {
        return true;
    }

    matches!(
        path.extension().and_then(|value| value.to_str()),
        Some("md" | "txt" | "yaml" | "yml" | "json")
    )
}

fn link_issues(vault: &Path) -> Result<Vec<LinkIssue>> {
    let files = collect_review_markdown_files(vault)?;
    let mut issues = Vec::new();

    for file in files {
        let abs = absolute_path(&file)?;
        let Some(rel) = rel_path(&abs, vault) else {
            continue;
        };
        let content = fs::read_to_string(&abs)?;
        for link in extract_review_links(&content) {
            if let Some(reason) = link_issue_reason(vault, &rel, &link) {
                issues.push(LinkIssue {
                    severity: severity_for_path(&rel).to_string(),
                    reason,
                    path: rel.clone(),
                    target: link.target,
                    line: link.line,
                });
            }
        }
    }

    Ok(issues)
}

fn unknown_tags(vault: &Path) -> Result<Vec<UnknownTag>> {
    let allowed = config::allowed_tags(vault)?;
    let files = collect_review_markdown_files(vault)?;
    let mut unknown = Vec::new();

    for file in files {
        let abs = absolute_path(&file)?;
        let Some(rel) = rel_path(&abs, vault) else {
            continue;
        };
        let content = fs::read_to_string(&abs)?;
        for tag in extract_frontmatter_tags(&content) {
            if let Some(similar) = unknown_tag_similar(&tag, &allowed) {
                unknown.push(UnknownTag {
                    path: rel.clone(),
                    tag,
                    similar,
                });
            }
        }
    }

    Ok(unknown)
}

fn unregistered_rooms(vault: &Path) -> Result<Vec<UnregisteredRoom>> {
    let patterns = config::room_patterns(vault)?;
    let files = collect_review_markdown_files(vault)?;
    let mut unregistered = Vec::new();

    for file in files {
        let abs = absolute_path(&file)?;
        let Some(rel) = rel_path(&abs, vault) else {
            continue;
        };
        if !is_strata_path(&rel) {
            continue;
        }
        let room = Path::new(&rel)
            .parent()
            .map(|path| path.to_string_lossy().to_string())
            .unwrap_or_else(|| ".".to_string());
        if !patterns
            .iter()
            .any(|pattern| room_matches_pattern(&room, pattern))
        {
            unregistered.push(UnregisteredRoom { path: rel, room });
        }
    }

    Ok(unregistered)
}

#[derive(Debug)]
struct ReviewLink {
    kind: LinkKind,
    target: String,
    line: i64,
}

#[derive(Debug)]
enum LinkKind {
    Markdown,
    WikiLink,
}

#[derive(Debug)]
struct LinkIssue {
    severity: String,
    reason: String,
    path: String,
    target: String,
    line: i64,
}

#[derive(Debug)]
struct PrivacyWarning {
    reason: String,
    path: String,
    line: i64,
    detail: String,
}

#[derive(Debug)]
struct UnknownTag {
    path: String,
    tag: String,
    similar: String,
}

#[derive(Debug)]
struct UnregisteredRoom {
    path: String,
    room: String,
}

fn is_strata_path(path: &str) -> bool {
    path.starts_with("1_draft/")
        || path.starts_with("2_knowledge/")
        || path.starts_with("3_intelligence/")
}

fn room_matches_pattern(room: &str, pattern: &str) -> bool {
    if let Some(prefix) = pattern.strip_suffix('*') {
        room.starts_with(prefix)
    } else {
        room == pattern || room.starts_with(&format!("{pattern}/"))
    }
}

fn extract_frontmatter_tags(content: &str) -> Vec<String> {
    let mut tags = Vec::new();
    let mut lines = content.lines();
    if lines.next() != Some("---") {
        return tags;
    }

    let mut in_tags = false;
    for line in lines {
        if line == "---" {
            break;
        }
        if line.starts_with("tags:") {
            in_tags = true;
            continue;
        }
        if in_tags && line.starts_with("  -") {
            let value = line
                .trim_start()
                .trim_start_matches('-')
                .trim_start()
                .trim_matches('"')
                .to_string();
            tags.push(value);
            continue;
        }
        if in_tags && !line.starts_with(' ') {
            break;
        }
    }

    tags
}

fn unknown_tag_similar(tag: &str, allowed: &[String]) -> Option<String> {
    let tag_lc = tag.to_ascii_lowercase();
    let tag_norm = normalize_tag(tag);
    let mut similar = String::new();

    for allowed_tag in allowed {
        let allowed_lc = allowed_tag.to_ascii_lowercase();
        let allowed_norm = normalize_tag(allowed_tag);
        if tag == allowed_tag {
            return None;
        }
        if tag_lc == allowed_lc || tag_norm == allowed_norm {
            similar = allowed_tag.clone();
        }
    }

    Some(similar)
}

fn normalize_tag(tag: &str) -> String {
    let mut normalized = tag
        .chars()
        .map(|ch| match ch {
            'A'..='Z' => ch.to_ascii_lowercase(),
            '_' | ' ' => '-',
            _ => ch,
        })
        .collect::<String>();
    while normalized.ends_with('-') {
        normalized.pop();
    }
    if normalized.ends_with('s') {
        normalized.pop();
    }
    normalized
}

fn privacy_warnings_for_file(path: &str, content: &str) -> Vec<PrivacyWarning> {
    let mut warnings = Vec::new();
    let mut log_lines = 0;
    let mut line_count = 0;

    for (line_idx, line) in content.lines().enumerate() {
        line_count = line_idx + 1;
        let line_no = line_count as i64;
        if line.contains("file://") {
            warnings.push(privacy_warning(
                "file_url",
                path,
                line_no,
                "file:// links expose local machine paths",
            ));
        }
        if contains_absolute_home_path(line) {
            warnings.push(privacy_warning(
                "absolute_home_path",
                path,
                line_no,
                "absolute home path found",
            ));
        }
        if line.contains("-----BEGIN ") && line.contains("PRIVATE KEY-----") {
            warnings.push(privacy_warning(
                "private_ssh_key",
                path,
                line_no,
                "private key block found",
            ));
        }
        if is_env_secret_assignment(line) {
            warnings.push(privacy_warning(
                "env_secret",
                path,
                line_no,
                "environment-style secret assignment found",
            ));
        }
        if is_api_key_like_assignment(line) {
            warnings.push(privacy_warning(
                "api_key_like",
                path,
                line_no,
                "API-key-like assignment found",
            ));
        }
        if contains_sk_prefixed_token(line) {
            warnings.push(privacy_warning(
                "api_key_like",
                path,
                line_no,
                "sk-prefixed token found",
            ));
        }
        if contains_log_level(line) {
            log_lines += 1;
        }
    }

    if line_count > 1200 && log_lines > 100 {
        warnings.push(privacy_warning(
            "large_pasted_log",
            path,
            1,
            "large log-like file found",
        ));
    }

    warnings
}

fn privacy_warning(reason: &str, path: &str, line: i64, detail: &str) -> PrivacyWarning {
    PrivacyWarning {
        reason: reason.to_string(),
        path: path.to_string(),
        line,
        detail: detail.to_string(),
    }
}

fn contains_absolute_home_path(line: &str) -> bool {
    for prefix in ["/home/", "/Users/"] {
        let mut search_start = 0;
        while let Some(pos) = line[search_start..].find(prefix) {
            let abs_pos = search_start + pos;
            let before = line[..abs_pos].chars().next_back();
            if before.is_none_or(|ch| !ch.is_ascii_alphanumeric() && ch != '_' && ch != '/') {
                return true;
            }
            search_start = abs_pos + prefix.len();
        }
    }

    let mut search_start = 0;
    while let Some(pos) = line[search_start..].find("/root") {
        let abs_pos = search_start + pos;
        let before = line[..abs_pos].chars().next_back();
        let after = line[abs_pos + "/root".len()..].chars().next();
        if before.is_none_or(|ch| !ch.is_ascii_alphanumeric() && ch != '_' && ch != '/')
            && after.is_none_or(|ch| ch == '/')
        {
            return true;
        }
        search_start = abs_pos + "/root".len();
    }
    false
}

fn is_env_secret_assignment(line: &str) -> bool {
    let trimmed = line.trim_start();
    let assignment = trimmed.strip_prefix("export ").unwrap_or(trimmed);
    let Some((name, _value)) = assignment.split_once('=') else {
        return false;
    };
    let name = name.trim_end();
    if name.is_empty() || !is_shell_identifier(name) {
        return false;
    }

    [
        "SECRET",
        "TOKEN",
        "PASSWORD",
        "PASS",
        "API_KEY",
        "ACCESS_KEY",
        "PRIVATE_KEY",
    ]
    .iter()
    .any(|needle| name.contains(needle))
}

fn is_shell_identifier(value: &str) -> bool {
    let mut chars = value.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if first != '_' && !first.is_ascii_alphabetic() {
        return false;
    }
    chars.all(|ch| ch == '_' || ch.is_ascii_alphanumeric())
}

fn is_api_key_like_assignment(line: &str) -> bool {
    let lower = line.to_ascii_lowercase();
    let Some(key_pos) = [
        "api_key",
        "api-key",
        "access_token",
        "access-token",
        "secret",
        "password",
        "bearer",
    ]
    .iter()
    .filter_map(|needle| lower.find(needle))
    .min() else {
        return false;
    };
    let rest = &line[key_pos..];
    let Some(sep_pos) = rest.find([':', '=']) else {
        return false;
    };
    let value = rest[sep_pos + 1..]
        .trim_start()
        .trim_start_matches(['"', '\'']);
    token_like_len(value) >= 20
}

fn contains_sk_prefixed_token(line: &str) -> bool {
    line.split(|ch: char| !ch.is_ascii_alphanumeric() && ch != '-')
        .any(|token| {
            token.strip_prefix("sk-").is_some_and(|suffix| {
                suffix.len() >= 20 && suffix.chars().all(|ch| ch.is_ascii_alphanumeric())
            })
        })
}

fn token_like_len(value: &str) -> usize {
    value
        .chars()
        .take_while(|ch| {
            ch.is_ascii_alphanumeric() || matches!(ch, '_' | '/' | '+' | '=' | '.' | '-')
        })
        .count()
}

fn contains_log_level(line: &str) -> bool {
    line.split(|ch: char| !ch.is_ascii_alphanumeric())
        .any(|token| {
            matches!(
                token,
                "TRACE" | "DEBUG" | "INFO" | "WARN" | "WARNING" | "ERROR" | "FATAL"
            )
        })
}

fn extract_review_links(content: &str) -> Vec<ReviewLink> {
    let mut links = Vec::new();
    for (line_idx, line) in content.lines().enumerate() {
        let line_no = (line_idx + 1) as i64;
        let mut rest = line;
        while let Some(open_text) = rest.find('[') {
            rest = &rest[open_text + 1..];
            let Some(close_text) = rest.find("](") else {
                continue;
            };
            rest = &rest[close_text + 2..];
            let Some(close_target) = rest.find(')') else {
                break;
            };
            let target = &rest[..close_target];
            rest = &rest[close_target + 1..];
            links.push(ReviewLink {
                kind: LinkKind::Markdown,
                target: target.to_string(),
                line: line_no,
            });
        }

        let mut rest = line;
        while let Some(open) = rest.find("[[") {
            rest = &rest[open + 2..];
            let Some(close) = rest.find("]]") else {
                break;
            };
            let target = &rest[..close];
            rest = &rest[close + 2..];
            links.push(ReviewLink {
                kind: LinkKind::WikiLink,
                target: target.to_string(),
                line: line_no,
            });
        }
    }
    links
}

fn link_issue_reason(vault: &Path, source_path: &str, link: &ReviewLink) -> Option<String> {
    match link.kind {
        LinkKind::WikiLink => Some("wikilink_not_allowed".to_string()),
        LinkKind::Markdown => {
            if link.target.starts_with("file://") {
                return Some("file_url_not_allowed".to_string());
            }
            if link.target.starts_with('/') {
                return Some("absolute_path_not_allowed".to_string());
            }
            if link.target.starts_with("http://") || link.target.starts_with("https://") {
                return None;
            }

            let clean = link
                .target
                .split('#')
                .next()
                .unwrap_or("")
                .split('?')
                .next()
                .unwrap_or("");
            if clean.is_empty() {
                return None;
            }

            let source_dir = Path::new(source_path)
                .parent()
                .unwrap_or_else(|| Path::new(""));
            let candidate = vault.join(source_dir).join(clean);
            if candidate.is_file() {
                None
            } else {
                Some("broken_local_link".to_string())
            }
        }
    }
}

fn severity_for_path(path: &str) -> &'static str {
    if path.starts_with("1_draft/") {
        "warn"
    } else {
        "error"
    }
}
