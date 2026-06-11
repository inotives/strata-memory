use crate::{absolute_path, collect_markdown_files_rec, json_escape, rel_path, Result};
use std::fs;
use std::path::{Path, PathBuf};

pub(crate) fn link_review(vault: &Path, json: bool) -> Result<()> {
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
