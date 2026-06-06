# Strata-Memory Commands

Core commands are installed under `0_core/script/`.

| Command | Purpose |
|---|---|
| `init.sh` | Create the vault folder structure and check bootstrap dependencies. |
| `doctor.sh` | Check vault health, dependencies, config, schema, reviews, and generated files. |
| `config-compile.sh` | Validate YAML config and write the derived JSON cache. |
| `db-migrate.sh` | Apply SQLite schema migrations into `0_core/db/strata.db`. |
| `normalize.sh` | Normalize constrained Markdown frontmatter for vault files. |
| `index.sh` | Index Markdown files, links, and sections into SQLite. |
| `search.sh` | Search indexed memory with FTS5 ranking and snippets. |
| `tag-review.sh` | Report unknown or similar tags. |
| `room-review.sh` | Report files outside registered room patterns. |
| `link-review.sh` | Report invalid and broken Markdown links. |
| `promote.sh` | Promote a draft into a durable tier and archive the source draft. |
| `agents-generate.sh` | Generate root `AGENTS.md` while preserving manual sections. |

Additional MVP commands will be added as implementation phases land.
