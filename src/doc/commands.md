# Strata-Memory Commands

Runtime commands are exposed by the installed Rust binary at `0_core/bin/strata`.
The one-off legacy migration helper remains under `0_core/script/migration.sh`.

| Command | Purpose |
|---|---|
| `strata init` | Create the vault folder structure and check bootstrap dependencies. |
| `strata doctor` | Check vault health, dependencies, config, schema, reviews, and generated files. |
| `strata config-compile` | Validate YAML config and write the derived JSON cache. |
| `strata db-migrate` | Apply SQLite schema migrations into `0_core/db/strata.db`. |
| `strata normalize` | Normalize constrained Markdown frontmatter for vault files. |
| `strata refresh` | Refresh the derived SQLite index with a full scan. |
| `strata index` | Index Markdown files, links, and sections into SQLite. |
| `strata search` | Search indexed memory with FTS5 ranking and snippets. Use `--refresh` for a one-shot full refresh before searching. |
| `strata tag-review` | Report unknown or similar tags. |
| `strata room-review` | Report files outside registered room patterns. |
| `strata link-review` | Report invalid and broken Markdown links. |
| `strata promote` | Promote a draft into a durable tier and archive the source draft. |
| `strata agents-generate` | Generate root `AGENTS.md` while preserving manual sections. |
| `strata retention` | Report or delete expired archived drafts. |
| `strata privacy-review` | Warn about private-data patterns before committing or sharing a vault. |
| `0_core/script/migration.sh` | Migrate selected legacy Agent Memory sections into a Strata vault. |
