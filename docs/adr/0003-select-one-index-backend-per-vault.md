# Select one index backend per vault

Each vault will select its active index backend through `index.backend: sqlite|turso` in `configs.yaml`, defaulting to `sqlite`. Commands will not accept per-invocation backend overrides because indexing and searching different backends would create inconsistent derived state; changing the configured backend requires rebuilding that backend's index.
