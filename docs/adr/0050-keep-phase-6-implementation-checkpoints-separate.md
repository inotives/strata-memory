# Keep Phase 6 implementation checkpoints separate

Phase 6 will use separate review checkpoints: Apple Silicon installer support; backend configuration and SQLite extraction; Turso dependency, migrations, and indexing; Turso full-text and vector search; and final evaluation. These concerns will not be collapsed into one change because separate checkpoints make platform, refactor, storage, and search regressions attributable.
