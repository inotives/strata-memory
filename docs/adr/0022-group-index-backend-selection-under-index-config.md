# Group backend selection under index configuration

Vault configuration will select the backend with `index.backend: sqlite|turso`, defaulting to `sqlite`, rather than a top-level backend key. The `index` section provides a stable home for future backend-neutral index settings without changing the configuration shape again.
