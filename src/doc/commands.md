# Strata-Memory Commands

Core commands are installed under `0_core/script/`.

| Command | Purpose |
|---|---|
| `init.sh` | Create the vault folder structure and check bootstrap dependencies. |
| `db-migrate.sh` | Apply SQLite schema migrations into `0_core/db/strata.db`. |
| `normalize.sh` | Normalize constrained Markdown frontmatter for vault files. |

Additional MVP commands will be added as implementation phases land.
