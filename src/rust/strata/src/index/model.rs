use serde::{Deserialize, Serialize};
use std::fmt;

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
