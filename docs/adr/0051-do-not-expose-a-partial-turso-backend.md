# Do not expose a partial Turso backend

`index.backend: turso` will remain unavailable to normal commands until Turso migrations, indexing, full-text search, semantic operations, status, and failure handling are all implemented. Intermediate PRs may exercise Turso through tests, but users will not be allowed to select a backend that can write an index without satisfying the complete query contract.
