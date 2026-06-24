use crate::{absolute_path, collect_markdown_files_rec, json_escape, rel_path, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum IndexBackend {
    #[default]
    Sqlite,
    Turso,
}

pub(crate) struct IndexSummary {
    pub(crate) backend: IndexBackend,
    pub(crate) indexed: usize,
}

pub(crate) struct SemanticRefreshSummary {
    pub(crate) backend: IndexBackend,
    pub(crate) provider: String,
    pub(crate) model: String,
    pub(crate) embedding_dim: i64,
    pub(crate) indexed: usize,
    pub(crate) descriptions: usize,
    pub(crate) sections: usize,
}

impl fmt::Display for IndexBackend {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Sqlite => formatter.write_str("sqlite"),
            Self::Turso => formatter.write_str("turso"),
        }
    }
}

pub(crate) struct Document {
    pub(crate) id: String,
    pub(crate) path: String,
    pub(crate) title: String,
    pub(crate) description: String,
    pub(crate) strata: String,
    pub(crate) status: String,
    pub(crate) tags: String,
    pub(crate) sources: String,
    pub(crate) source_note: String,
    pub(crate) version: i64,
    pub(crate) last_edit_summary: String,
    pub(crate) created: String,
    pub(crate) modified: String,
    pub(crate) content: String,
    pub(crate) content_hash: String,
}

pub(crate) struct Link {
    pub(crate) target: String,
    pub(crate) target_type: String,
    pub(crate) text: String,
    pub(crate) line: i64,
}

pub(crate) struct Section {
    pub(crate) heading: String,
    pub(crate) level: i64,
    pub(crate) start_line: i64,
    pub(crate) end_line: i64,
    pub(crate) content: String,
}

pub(crate) struct IndexedDocument {
    pub(crate) document: Document,
    pub(crate) links: Vec<Link>,
    pub(crate) sections: Vec<Section>,
}

pub(crate) fn collect_markdown_files(vault: &Path) -> Result<Vec<PathBuf>> {
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

pub(crate) fn read_document(vault: &Path, file: &Path) -> Result<Option<IndexedDocument>> {
    if !file.is_file() || file.extension().and_then(|ext| ext.to_str()) != Some("md") {
        return Ok(None);
    }

    let abs = absolute_path(file)?;
    let Some(rel) = rel_path(&abs, vault) else {
        return Ok(None);
    };
    let Some(strata) = detect_strata(&rel) else {
        return Ok(None);
    };
    if is_excluded_path(&rel) {
        return Ok(None);
    }

    let content = fs::read_to_string(&abs)?;
    let frontmatter = parse_frontmatter(&content);
    Ok(Some(IndexedDocument {
        document: build_document(&abs, &rel, strata, &content, &frontmatter)?,
        links: extract_links(&content),
        sections: extract_sections(&content),
    }))
}

pub(crate) fn build_document(
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

#[derive(Default, Debug)]
pub(crate) struct Frontmatter {
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

pub(crate) fn parse_frontmatter(content: &str) -> Frontmatter {
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

pub(crate) fn unquote(value: &str) -> String {
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        value[1..value.len() - 1].to_string()
    } else {
        value.to_string()
    }
}

pub(crate) fn json_array(values: &[String]) -> String {
    let body = values
        .iter()
        .map(|value| format!("\"{}\"", json_escape(value)))
        .collect::<Vec<_>>()
        .join(",");
    format!("[{body}]")
}

pub(crate) fn extract_links(content: &str) -> Vec<Link> {
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

pub(crate) fn extract_sections(content: &str) -> Vec<Section> {
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

pub(crate) fn parse_heading(line: &str) -> Option<(i64, String)> {
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

pub(crate) fn detect_strata(rel: &str) -> Option<&'static str> {
    match rel {
        path if path.starts_with("0_core/") => Some("0_core"),
        path if path.starts_with("1_draft/") => Some("1_draft"),
        path if path.starts_with("2_knowledge/") => Some("2_knowledge"),
        path if path.starts_with("3_intelligence/") => Some("3_intelligence"),
        _ => None,
    }
}

pub(crate) fn is_excluded_path(rel: &str) -> bool {
    rel.starts_with("0_core/cache/")
        || rel.starts_with("0_core/tmp/")
        || rel.starts_with("0_core/test/tmp/")
        || rel.starts_with("0_core/db/")
}

pub(crate) fn default_status(strata: &str, rel: &str) -> &'static str {
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

pub(crate) fn valid_status(status: &str) -> bool {
    matches!(
        status,
        "pending" | "verified" | "archived" | "generated" | "core"
    )
}

pub(crate) fn make_id(rel: &str) -> String {
    let stamp = unix_timestamp();
    let crc = posix_cksum(rel.as_bytes());
    format!("mem_{stamp}_{crc}")
}

pub(crate) fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

pub(crate) fn posix_cksum_hash(bytes: &[u8]) -> String {
    format!("{}:{}", posix_cksum(bytes), bytes.len())
}

pub(crate) fn posix_cksum(bytes: &[u8]) -> u32 {
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
