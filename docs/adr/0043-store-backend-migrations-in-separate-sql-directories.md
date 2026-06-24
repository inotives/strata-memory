# Store backend migrations in separate SQL directories

SQLite migrations will live under `src/db/sqlite/` and Turso migrations under `src/db/turso/`, with the active backend embedding and applying its own ordered SQL files. Schema migrations remain reviewable SQL assets rather than generated Rust strings.
