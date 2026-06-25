use crate::Result;
use std::fs;
use std::path::Path;
use std::process::Command;

const BOOTSTRAP_DEPENDENCIES: &[&str] = &[
    "bash", "sqlite3", "awk", "sed", "find", "sort", "mktemp", "cksum", "date",
];

const VAULT_DIRS: &[&str] = &[
    "0_core/config",
    "0_core/cache",
    "0_core/db/sqlite/migrations",
    "0_core/db/turso/migrations",
    "0_core/doc",
    "0_core/script/lib",
    "0_core/template",
    "0_core/template_override",
    "0_core/test/tmp",
    "0_core/tmp",
    "1_draft/research",
    "1_draft/note",
    "1_draft/skill",
    "1_draft/agent",
    "1_draft/workflow",
    "1_draft/session",
    "1_draft/_archived",
    "2_knowledge/concept",
    "2_knowledge/entity",
    "2_knowledge/research",
    "2_knowledge/note",
    "2_knowledge/preference",
    "2_knowledge/_archived",
    "3_intelligence/skill",
    "3_intelligence/agent",
    "3_intelligence/workflow",
    "3_intelligence/report",
    "3_intelligence/_archived",
];

pub(crate) fn init(vault: &Path) -> Result<()> {
    check_bootstrap_dependencies()?;
    for rel in VAULT_DIRS {
        fs::create_dir_all(vault.join(rel))?;
    }
    Ok(())
}

fn check_bootstrap_dependencies() -> Result<()> {
    for dep in BOOTSTRAP_DEPENDENCIES {
        if !command_exists(dep) {
            return Err(format!("missing required dependency: {dep}").into());
        }
    }
    Ok(())
}

fn command_exists(command: &str) -> bool {
    Command::new("sh")
        .arg("-c")
        .arg("command -v \"$1\" >/dev/null 2>&1")
        .arg("sh")
        .arg(command)
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}
