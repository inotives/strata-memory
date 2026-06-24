# Evaluate Turso before replacing SQLite

SQLite/rusqlite will remain Strata's default index backend, while embedded local Turso is introduced as an opt-in alternative. This phase is a capability and parity evaluation: Turso may replace SQLite only after it reproduces Strata's indexing, full-text search, filtering, snippets, refresh, and hybrid-search contracts and proves reliable on representative vault copies.
