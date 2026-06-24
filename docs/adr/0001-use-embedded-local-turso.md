# Use embedded local Turso

Strata will replace `rusqlite` with the embedded Rust `turso` crate while retaining a local `0_core/db/strata.db` database. This phase will not add Turso Cloud, remote databases, replication, or synchronization because Strata's vault remains local-first and the immediate goal is native vector operations without introducing network availability, authentication, or data-residency concerns.
