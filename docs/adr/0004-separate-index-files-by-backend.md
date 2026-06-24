# Keep separate index files for Turso and SQLite

The Turso backend will use `0_core/db/strata-turso.db`, while the retained SQLite backend will continue using `0_core/db/strata.db`. Switching `index.backend` will neither convert data nor silently fall back to the other backend; `strata refresh` rebuilds the selected backend from the Markdown vault.
