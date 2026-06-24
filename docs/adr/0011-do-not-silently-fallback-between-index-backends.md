# Do not silently fall back between index backends

When `index.backend: turso` is selected, initialization or query failures will stop with a clear error that instructs the user to set `index.backend: sqlite` and run `strata refresh`. Strata will not silently query the SQLite index because it may be absent or stale and would make the configured backend contract unreliable.
