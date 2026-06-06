# Strata-Memory Commands

Core commands are installed under `0_core/script/`.

| Command | Purpose |
|---|---|
| `init.sh` | Create the vault folder structure and check bootstrap dependencies. |
| `db-migrate.sh` | Apply SQLite schema migrations into `0_core/db/strata.db`. |
| `normalize.sh` | Normalize constrained Markdown frontmatter for vault files. |
| `index.sh` | Index Markdown files, links, and sections into SQLite. |
| `search.sh` | Search indexed memory with FTS5 ranking and snippets. |
| `tag-review.sh` | Report unknown or similar tags. |
| `room-review.sh` | Report files outside registered room patterns. |
| `link-review.sh` | Report invalid and broken Markdown links. |

Additional MVP commands will be added as implementation phases land.
