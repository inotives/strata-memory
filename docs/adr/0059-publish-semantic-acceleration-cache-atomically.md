# Publish the semantic acceleration cache atomically

`strata semantic-refresh` will commit authoritative SQLite embeddings before publishing HNSW artifacts. It builds graph and manifest files under unique temporary names, flushes and closes both, renames the graph into place, and renames the manifest last as the commit marker. Search trusts only a graph whose manifest validates. Failed cache publication leaves exact semantic search available, and a later semantic refresh removes abandoned temporary files.
