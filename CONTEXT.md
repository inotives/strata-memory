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
