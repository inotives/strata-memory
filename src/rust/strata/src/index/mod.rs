pub(crate) mod model;
mod sqlite;
mod turso;

pub(crate) use sqlite::posix_cksum;

use crate::cli::{IndexMode, SearchArgs};
use crate::config;
use crate::Result;
use model::{IndexBackend, IndexSummary, SemanticRefreshSummary};
use std::path::{Path, PathBuf};

pub(crate) struct ActiveIndex {
    pub(crate) backend: IndexBackend,
    pub(crate) db_path: PathBuf,
    pub(crate) applied: usize,
}

pub(crate) struct IndexInfo {
    pub(crate) backend: IndexBackend,
    pub(crate) db_path: PathBuf,
    pub(crate) experimental: bool,
}

pub(crate) fn configured(vault: &Path) -> Result<IndexInfo> {
    match config::index_backend(vault)? {
        IndexBackend::Sqlite => Ok(IndexInfo {
            backend: IndexBackend::Sqlite,
            db_path: sqlite::database_path(vault),
            experimental: false,
        }),
        IndexBackend::Turso => Ok(IndexInfo {
            backend: IndexBackend::Turso,
            db_path: turso::database_path(vault),
            experimental: true,
        }),
    }
}

pub(crate) fn active(vault: &Path) -> Result<ActiveIndex> {
    match configured(vault)?.backend {
        IndexBackend::Sqlite => Ok(ActiveIndex {
            backend: IndexBackend::Sqlite,
            db_path: sqlite::database_path(vault),
            applied: 0,
        }),
        IndexBackend::Turso => turso::unavailable(),
    }
}

pub(crate) fn migrate(vault: &Path) -> Result<ActiveIndex> {
    match configured(vault)?.backend {
        IndexBackend::Sqlite => Ok(ActiveIndex {
            backend: IndexBackend::Sqlite,
            db_path: sqlite::database_path(vault),
            applied: sqlite::migrate(vault)?,
        }),
        IndexBackend::Turso => turso::unavailable(),
    }
}

pub(crate) fn refresh(vault: &Path, mode: IndexMode) -> Result<IndexSummary> {
    match config::index_backend(vault)? {
        IndexBackend::Sqlite => Ok(IndexSummary {
            backend: IndexBackend::Sqlite,
            indexed: sqlite::refresh(vault, mode)?,
        }),
        IndexBackend::Turso => turso::unavailable(),
    }
}

pub(crate) fn search(vault: &Path, args: &SearchArgs, json: bool) -> Result<()> {
    match config::index_backend(vault)? {
        IndexBackend::Sqlite => sqlite::search(vault, args, json),
        IndexBackend::Turso => turso::unavailable(),
    }
}

pub(crate) fn semantic_refresh(vault: &Path) -> Result<SemanticRefreshSummary> {
    match config::index_backend(vault)? {
        IndexBackend::Sqlite => sqlite::semantic_refresh(vault),
        IndexBackend::Turso => turso::unavailable(),
    }
}

pub(crate) fn semantic_status(vault: &Path, json: bool) -> Result<()> {
    match config::index_backend(vault)? {
        IndexBackend::Sqlite => sqlite::semantic_status(vault, json),
        IndexBackend::Turso => turso::unavailable(),
    }
}
