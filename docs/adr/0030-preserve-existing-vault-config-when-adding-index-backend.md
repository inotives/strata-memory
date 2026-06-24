# Preserve existing vault configuration when adding index backend selection

The installer will continue treating `configs.yaml` as user-owned and will not insert or rewrite `index.backend` in existing vaults. New-vault templates include `index.backend: sqlite`, while existing vaults use the missing-key default of SQLite until the user explicitly opts into Turso.
