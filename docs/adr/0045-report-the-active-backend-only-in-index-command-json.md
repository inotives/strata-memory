# Report the active backend only in index command JSON

JSON output for `db-migrate`, `index`, `refresh`, `search`, `semantic-refresh`, `semantic-status`, and `doctor` will include `backend: sqlite|turso`. Unrelated commands retain their existing JSON schemas because backend identity has no meaning outside index operations.
