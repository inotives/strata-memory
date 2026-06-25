# Keep semantic acceleration rebuilds out of search

Search will validate the persisted semantic acceleration cache against a deterministic identity derived from authoritative SQLite embedding records. Missing, stale, incompatible, or unreadable cache artifacts fall back to exact semantic search. Search never rebuilds HNSW because an unexpected graph build would make query latency unbounded; `strata semantic-refresh` is the explicit rebuild command.
