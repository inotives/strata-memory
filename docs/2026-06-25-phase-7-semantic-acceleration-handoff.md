# Phase 7 Semantic Acceleration Handoff

## Current State

- Repository: `/Users/inotives/workspaces/strata-memory`
- Branch: `main`
- Latest commit: `b851df2 docs: plan semantic acceleration evaluation`
- Local `main` is one commit ahead of `origin/main`; the Phase 7 planning commit has not been pushed.
- Phase 6 is merged and complete. SQLite remains the default index backend; Turso remains experimental and opt-in.
- The installed binary under `~/.strata-memory/0_core/bin/strata` predates Phase 7, which currently contains documentation only.

## Authoritative Phase 7 Documents

- Implementation design: [phase-7-semantic-acceleration-evaluation.md](phase-7-semantic-acceleration-evaluation.md)
- Project roadmap: [implementation_plan.md](implementation_plan.md)
- Product specification: [project_spec.md](project_spec.md)
- Domain language: [CONTEXT.md](../CONTEXT.md)
- Durable decisions:
  - [ADR-0056](adr/0056-gate-approximate-semantic-search-on-measured-latency.md)
  - [ADR-0057](adr/0057-keep-semantic-acceleration-rebuilds-out-of-search.md)
  - [ADR-0059](adr/0059-publish-semantic-acceleration-cache-atomically.md)
  - [ADR-0060](adr/0060-select-hnsw-automatically-with-exact-fallback.md)
  - [ADR-0061](adr/0061-require-all-hnsw-promotion-gates.md)

Do not redesign from the conversation history. The Phase 7 document contains the resolved decisions, five gated checkpoints, required platform matrix, promotion gates, and exit verdicts.

## Next Work

1. Commit this handoff and push `main` if requested.
2. Start Phase 7 on a new feature branch.
3. Implement only Checkpoint 1: shared Rust library target with no behavior change.
4. Move the installed CLI entry point to `src/bin/strata.rs` and expose shared modules through `src/lib.rs`.
5. Run the full existing SQLite, Turso, Apple Silicon, and Linux correctness suites.
6. Stop for review before Checkpoint 2.

HNSW is not guaranteed scope. Exact semantic search must be benchmarked first, and production `hnsw_rs` must not be added unless the documented latency trigger and compatibility spike justify it.

## Constraints

- Use CodeGraph before exploring or editing indexed code.
- Use context-mode for large outputs and test runs.
- Preserve SQLite as authoritative storage and default backend.
- Keep Turso behavior unchanged.
- Preserve all CLI commands, installed binary name, output contracts, and existing tests during Checkpoint 1.
- Keep changes minimal; do not combine library refactoring with semantic extraction or benchmarking.

## Suggested Skills

- `codebase-design` for the library and semantic module seams.
- `tdd` for each checkpoint and parity contract.
- `context-mode` for tests and large diffs.
- `diagnosing-bugs` if the library move changes behavior or performance.
- `agent-reach` only when refreshing current `hnsw_rs` upstream evidence.

## Verification Before Handoff Completion

Run:

```bash
git status --short --branch
git log -1 --oneline --decorate
git diff --check
```

Expected before committing this file: `main` is ahead of `origin/main` by the Phase 7 planning commit, and this handoff is the only new untracked file.
