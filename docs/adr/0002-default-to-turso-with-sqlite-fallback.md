---
status: superseded by ADR-0005
---

# Default to Turso with a SQLite fallback

Strata will add Turso as a new index backend and make it the default while retaining the existing SQLite/rusqlite backend as an explicit fallback. Each backend owns a separate rebuildable index database; Strata will not migrate an existing SQLite index into Turso or allow both backends to write the same database file, because all index state can be regenerated from the Markdown vault.
