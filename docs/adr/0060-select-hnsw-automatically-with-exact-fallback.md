# Select HNSW automatically with exact fallback

The first semantic acceleration implementation will not expose an engine configuration option. Hybrid search uses HNSW when a valid acceleration cache is available and otherwise runs exact Rust semantic search. Text output remains quiet because semantic results are still available; JSON output reports the selected semantic engine, and `strata semantic-status` explains cache readiness or staleness. Missing HNSW never forces an FTS-only fallback while authoritative embeddings remain usable.
