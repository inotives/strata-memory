use crate::{config, Result};
use std::fs;
use std::path::{Path, PathBuf};

const GENERATED_START: &str = "<!-- STRATA_GENERATED_START -->";
const GENERATED_END: &str = "<!-- STRATA_GENERATED_END -->";
const MANUAL_START: &str = "<!-- STRATA_MANUAL_START -->";
const MANUAL_END: &str = "<!-- STRATA_MANUAL_END -->";

pub(crate) struct GenerateSummary {
    pub(crate) path: String,
    pub(crate) profile: String,
}

pub(crate) fn generate(vault: &Path) -> Result<GenerateSummary> {
    let core = vault.join("0_core");
    let target = vault.join("AGENTS.md");
    let base = core.join("template/agents/base.md");
    let tmp_dir = core.join("tmp");

    if !base.is_file() {
        return Err(format!("missing AGENTS base template: {}", base.to_string_lossy()).into());
    }
    fs::create_dir_all(&tmp_dir)?;

    let base_content = fs::read_to_string(&base)?;
    let manual = if target.is_file() {
        let target_content = fs::read_to_string(&target)?;
        extract_block(&target_content, MANUAL_START, MANUAL_END)
            .or_else(|| extract_block(&base_content, MANUAL_START, MANUAL_END))
            .unwrap_or_else(default_manual)
    } else {
        extract_block(&base_content, MANUAL_START, MANUAL_END).unwrap_or_else(default_manual)
    };

    let (profile, tier2_rooms) = config::profile_tier2_rooms(vault)?;
    let generated = generated_block(&core, &profile, &tier2_rooms)?;
    let output = replace_generated_and_manual(&base_content, &generated, &manual);

    let tmp_path = tmp_dir.join(format!("agents-output-{}", std::process::id()));
    fs::write(&tmp_path, output)?;
    fs::rename(&tmp_path, &target)?;

    Ok(GenerateSummary {
        path: "AGENTS.md".to_string(),
        profile,
    })
}

fn extract_block(content: &str, start: &str, end: &str) -> Option<String> {
    let mut out = Vec::new();
    let mut in_block = false;
    let mut found = false;

    for line in content.lines() {
        if line == start {
            in_block = true;
            out.push(line.to_string());
            continue;
        }
        if line == end && in_block {
            out.push(line.to_string());
            found = true;
            break;
        }
        if in_block {
            out.push(line.to_string());
        }
    }

    found.then(|| {
        let mut block = out.join("\n");
        block.push('\n');
        block
    })
}

fn default_manual() -> String {
    format!("{MANUAL_START}\nAdd vault-specific instructions here.\n{MANUAL_END}\n")
}

fn generated_block(core: &Path, profile: &str, tier2_rooms: &[String]) -> Result<String> {
    let mut out = String::new();
    out.push_str(GENERATED_START);
    out.push('\n');
    out.push_str("## Structure\n");
    out.push_str("```text\n");
    out.push_str(
        "0_core/            Kernel: config, scripts, schema, templates, docs, cache, tmp.\n",
    );
    out.push_str("1_draft/           Tier 1: raw, unreviewed, ephemeral material.\n");
    out.push_str("2_knowledge/       Tier 2: curated, reviewed, durable knowledge.\n");
    out.push_str("3_intelligence/    Tier 3: skills, agents, workflows, and generated reports.\n");
    out.push_str("```\n\n");
    out.push_str("## Active Profile\n\n");
    out.push_str(&format!("Profile: `{profile}`\n\n"));

    let profile_template = profile_template(core, profile);
    if profile_template.is_file() {
        out.push_str(&fs::read_to_string(profile_template)?);
        if !out.ends_with('\n') {
            out.push('\n');
        }
        out.push('\n');
    }

    out.push_str("## Registered Tier 2 Rooms\n\n");
    for room in tier2_rooms {
        if !room.is_empty() {
            out.push_str(&format!("- `{room}`\n"));
        }
    }
    out.push('\n');
    out.push_str("## Strata Commands\n\n");
    out.push_str("Core commands are namespaced in generated command tables.\n\n");
    out.push_str("| Command | Usage |\n");
    out.push_str("|---|---|\n");
    out.push_str("| `strata:init` | Initialize vault structure and bootstrap config. |\n");
    out.push_str("| `strata:doctor` | Check vault health, dependencies, config, schema, rooms, tags, and generated files. |\n");
    out.push_str("| `strata:index` | Index target files or run a full scan. |\n");
    out.push_str("| `strata:search` | Search indexed memory. |\n");
    out.push_str("| `strata:promote` | Promote drafts into knowledge or intelligence. |\n");
    out.push_str("| `strata:tag-review` | Review unknown or similar tags. |\n");
    out.push_str("| `strata:room-review` | Review unregistered rooms. |\n");
    out.push_str("| `strata:link-review` | Review invalid or broken vault links. |\n");
    out.push_str(
        "| `strata:migrate` | Migrate selected sections from `~/.agent-knowledge/memory`. |\n",
    );
    out.push_str("| `strata:agents-generate` | Generate `AGENTS.md` from templates, profile, config, and manual sections. |\n");
    out.push_str("\nFull generated command docs live at `0_core/doc/commands.md`.\n");
    out.push_str(GENERATED_END);
    out.push('\n');
    Ok(out)
}

fn profile_template(core: &Path, profile: &str) -> PathBuf {
    core.join("template/agents/profile")
        .join(format!("{profile}.md"))
}

fn replace_generated_and_manual(base: &str, generated: &str, manual: &str) -> String {
    let mut out = String::new();
    let mut in_generated = false;
    let mut in_manual = false;

    for line in base.lines() {
        if line == GENERATED_START {
            out.push_str(generated);
            in_generated = true;
            continue;
        }
        if line == GENERATED_END && in_generated {
            in_generated = false;
            continue;
        }
        if line == MANUAL_START {
            out.push_str(manual);
            in_manual = true;
            continue;
        }
        if line == MANUAL_END && in_manual {
            in_manual = false;
            continue;
        }
        if in_generated || in_manual {
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }

    out
}
