# Strata Memory

Strata Memory manages a local-first knowledge vault and its rebuildable search infrastructure.

## Language

**Index backend**:
The storage and query implementation used for Strata's rebuildable search index, including metadata, full-text search, and semantic vectors.
_Avoid_: Database engine, indexer

**Active index backend**:
The single index backend selected by a vault configuration for all index reads, writes, migrations, and searches.
_Avoid_: Default database, current indexer

**Index rebuild**:
Regeneration of the active backend's complete derived index from the Markdown vault. It does not convert or copy index state between backends.
_Avoid_: Database migration, backend migration

**Index database**:
The rebuildable local database file owned by an index backend.
_Avoid_: Turso database, primary database, source of truth

**Semantic acceleration cache**:
A disposable search structure and its freshness manifest, derived from embeddings in the active index database to reduce semantic query latency. It is never authoritative and may be deleted or rebuilt without losing memory.
_Avoid_: Vector database, semantic backend, source of truth

**Exact semantic search**:
Semantic retrieval that compares a query vector with every eligible stored embedding.
_Avoid_: Brute-force database search

**Approximate semantic search**:
Semantic retrieval that uses a derived nearest-neighbor structure to reduce comparisons while accepting measurable recall loss.
_Avoid_: Exact vector search
