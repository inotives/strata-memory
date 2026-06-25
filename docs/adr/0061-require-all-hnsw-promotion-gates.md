# Require all HNSW promotion gates

Strata enables automatic HNSW use only when the candidate passes every documented correctness, latency, startup, memory, disk-size, and rebuild gate. The required quality floor is 95% recall@10 and the same top result on at least 95% of deterministic queries, with exact metadata and archive filtering. Any failed gate keeps exact Rust semantic search as the production path.
