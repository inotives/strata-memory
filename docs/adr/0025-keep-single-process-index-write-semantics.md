# Keep single-process index write semantics

Phase 6 preserves Strata's current single-process CLI write model for both index backends. It will not add multi-process coordination or concurrent-writer orchestration; overlapping commands must fail with a clear lock or busy error and must not corrupt either backend's rebuildable index.
