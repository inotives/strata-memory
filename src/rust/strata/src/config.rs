use crate::Result;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Deserialize, Serialize)]
struct Config {
    profile: String,
    retention: Retention,
    tags: Tags,
    rooms: BTreeMap<String, Vec<RoomConfig>>,
    profiles: BTreeMap<String, Profile>,
}

#[derive(Debug, Deserialize, Serialize)]
struct Retention {
    archived_drafts_days: i64,
    default_mode: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct Tags {
    allowed: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct RoomConfig {
    path: String,
    #[serde(default)]
    description: String,
    #[serde(default = "default_depth")]
    depth: String,
    #[serde(default)]
    required_files: Vec<String>,
    #[serde(default)]
    allowed_status: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct Profile {
    tier2_rooms: Vec<String>,
}

#[derive(Debug, Serialize)]
struct CompiledRoom {
    tier: String,
    path: String,
    pattern: String,
    description: String,
    depth: String,
    required_files: Vec<String>,
    allowed_status: Vec<String>,
}

pub(crate) struct CompileSummary {
    pub(crate) cache: PathBuf,
    pub(crate) profile: String,
    pub(crate) rooms: usize,
    pub(crate) tags: usize,
}

pub(crate) fn profile_tier2_rooms(vault: &Path) -> Result<(String, Vec<String>)> {
    let config_path = vault.join("0_core/config/configs.yaml");
    if !config_path.is_file() {
        return Err(format!("missing config: {}", config_path.to_string_lossy()).into());
    }

    let yaml = fs::read_to_string(&config_path).map_err(|err| {
        format!(
            "Unable to parse config YAML: {}: {err}",
            config_path.display()
        )
    })?;
    let config: Config = serde_yaml::from_str(&yaml).map_err(|err| {
        format!(
            "Unable to parse config YAML: {}: {err}",
            config_path.display()
        )
    })?;
    let profile = if config.profile.is_empty() {
        "default".to_string()
    } else {
        config.profile
    };
    let rooms = config
        .profiles
        .get(&profile)
        .map(|profile| profile.tier2_rooms.clone())
        .unwrap_or_default();

    Ok((profile, rooms))
}

pub(crate) fn compile(vault: &Path) -> Result<CompileSummary> {
    let config_path = vault.join("0_core/config/configs.yaml");
    let cache_path = vault.join("0_core/cache/config.compiled.json");
    let tmp_dir = vault.join("0_core/tmp");

    if !config_path.is_file() {
        return Err(format!("Config not found: {}", config_path.to_string_lossy()).into());
    }

    fs::create_dir_all(cache_path.parent().ok_or("invalid config cache path")?)?;
    fs::create_dir_all(&tmp_dir)?;

    let yaml = fs::read_to_string(&config_path).map_err(|err| {
        format!(
            "Unable to parse config YAML: {}: {err}",
            config_path.display()
        )
    })?;
    let config: Config = serde_yaml::from_str(&yaml).map_err(|err| {
        format!(
            "Unable to parse config YAML: {}: {err}",
            config_path.display()
        )
    })?;

    let rooms = validate_and_flatten(&config).map_err(|message| {
        format!(
            "Config validation failed: {}\n{message}",
            config_path.display()
        )
    })?;

    let mut tags = config.tags.allowed.clone();
    tags.sort();
    let profile = config.profile.clone();
    let room_count = rooms.len();
    let tag_count = tags.len();

    let compiled = json!({
        "generated_at": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "source": "0_core/config/configs.yaml",
        "profile": profile,
        "retention": config.retention,
        "tags": {"allowed": tags},
        "rooms": rooms,
        "profiles": config.profiles,
    });

    let tmp_path = tmp_dir.join(format!("config-compiled-{}.json", std::process::id()));
    fs::write(&tmp_path, serde_json::to_string_pretty(&compiled)?)?;
    fs::rename(&tmp_path, &cache_path)?;

    Ok(CompileSummary {
        cache: cache_path,
        profile,
        rooms: room_count,
        tags: tag_count,
    })
}

fn validate_and_flatten(config: &Config) -> Result<Vec<CompiledRoom>> {
    require(
        !config.profile.is_empty(),
        "profile must be a non-empty string",
    )?;
    require(
        config.retention.archived_drafts_days >= 1,
        "retention.archived_drafts_days must be a positive number",
    )?;
    require(
        config.retention.default_mode.as_deref().unwrap_or("report") == "report",
        "retention.default_mode must be report for MVP",
    )?;
    require(
        !config.tags.allowed.is_empty(),
        "tags.allowed must be a non-empty array",
    )?;
    require(
        config.tags.allowed.iter().all(|tag| lower_token(tag)),
        "tags.allowed values must be lowercase tokens",
    )?;
    require(
        unique(config.tags.allowed.iter().map(String::as_str)),
        "tags.allowed values must be unique",
    )?;

    for tier in ["1_draft", "2_knowledge", "3_intelligence"] {
        require(
            config.rooms.contains_key(tier),
            &format!("rooms.{tier} must be an array"),
        )?;
    }

    let mut rooms = Vec::new();
    for (tier, tier_rooms) in &config.rooms {
        require(
            matches!(tier.as_str(), "1_draft" | "2_knowledge" | "3_intelligence"),
            "rooms may only use tier keys 1_draft, 2_knowledge, 3_intelligence",
        )?;
        for room in tier_rooms {
            require(
                room_path_ok(&room.path),
                "room paths must be lowercase relative paths without ..",
            )?;
            require(
                matches!(room.depth.as_str(), "recursive" | "exact"),
                "room depth must be recursive or exact",
            )?;
            rooms.push(CompiledRoom {
                tier: tier.clone(),
                path: room.path.clone(),
                pattern: format!("{tier}/{}", room.path),
                description: room.description.clone(),
                depth: room.depth.clone(),
                required_files: room.required_files.clone(),
                allowed_status: room.allowed_status.clone(),
            });
        }
    }

    require(
        unique(rooms.iter().map(|room| room.pattern.as_str())),
        "room patterns must be unique",
    )?;
    require(!config.profiles.is_empty(), "profiles must be an object")?;
    require(
        config.profiles.contains_key(&config.profile),
        "active profile must exist under profiles",
    )?;

    let tier2_rooms: HashSet<&str> = rooms
        .iter()
        .filter(|room| room.tier == "2_knowledge")
        .map(|room| room.path.as_str())
        .collect();
    for profile in config.profiles.values() {
        for room in &profile.tier2_rooms {
            require(
                tier2_rooms.contains(room.as_str()),
                "profile tier2_rooms must reference rooms.2_knowledge paths",
            )?;
        }
    }

    Ok(rooms)
}

fn require(condition: bool, message: &str) -> Result<()> {
    if condition {
        Ok(())
    } else {
        Err(message.to_string().into())
    }
}

fn unique<'a>(values: impl Iterator<Item = &'a str>) -> bool {
    let mut seen = HashSet::new();
    values.into_iter().all(|value| seen.insert(value))
}

fn lower_token(value: &str) -> bool {
    let mut chars = value.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    (first.is_ascii_lowercase() || first.is_ascii_digit())
        && chars.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
}

fn room_path_ok(value: &str) -> bool {
    !value.is_empty()
        && !value.starts_with('/')
        && !value.contains("..")
        && value.chars().all(|ch| {
            ch.is_ascii_lowercase() || ch.is_ascii_digit() || matches!(ch, '_' | '*' | '/' | '-')
        })
}

fn default_depth() -> String {
    "recursive".to_string()
}
