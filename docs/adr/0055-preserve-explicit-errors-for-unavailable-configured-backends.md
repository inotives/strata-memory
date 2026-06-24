# Preserve explicit errors for unavailable configured backends

If a future build no longer includes Turso, configuration parsing will still recognize `index.backend: turso` and commands will fail with guidance to select SQLite and run `strata refresh`. Strata will not silently reinterpret the configured backend as SQLite because that could query stale or unintended index state.
