use crate::Result;
use std::path::{Path, PathBuf};

pub(super) fn database_path(vault: &Path) -> PathBuf {
    vault.join("0_core/db/strata-turso.db")
}

pub(super) fn unavailable<T>() -> Result<T> {
    Err(
        "index backend turso is not available yet; set index.backend: sqlite and run strata refresh"
            .into(),
    )
}
