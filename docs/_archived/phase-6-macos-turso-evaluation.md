# Phase 6: Apple Silicon macOS and Turso Index Backend Evaluation

## Goal

Add supported Apple Silicon macOS installation and evaluate embedded local Turso as a complete, opt-in index backend without weakening the existing SQLite/rusqlite default.

This phase determines whether Turso can eventually replace SQLite. It does not make that replacement.

## Decisions

- SQLite/rusqlite remains the default index backend.
- One `strata` binary includes both backends.
- `index.backend: sqlite|turso` selects one backend for the entire vault; the default is `sqlite`.
- SQLite uses `0_core/db/strata.db`.
- Turso uses `0_core/db/strata-turso.db`.
- Index databases are derived state and are rebuilt from Markdown. They are not converted between backends.
- Embedded local Turso is in scope. Turso Cloud, replication, synchronization, authentication, and remote databases are not.
- Turso implements the complete user-visible indexing and search contract, not a benchmark-only prototype.
- A selected backend never silently falls back to the other backend.
- Index writes retain the current single-process command model; overlapping writers fail clearly without corruption.
- Turso exact vector distance functions are in scope. Custom approximate-nearest-neighbor indexing is not.
- macOS support targets Apple Silicon (`aarch64-apple-darwin`) only.
- The existing installer builds and installs locally. Homebrew, prebuilt artifacts, signing, and notarization are deferred.

The supporting records are in `docs/adr/0001-*.md` through `docs/adr/0055-*.md`.

## Required Behavior

User-facing output uses the terms `index backend` and `index database`. Markdown remains the source of truth; Turso is not presented as a separate Strata product mode.

All commands that read or write the derived index must use the active index backend:

- `strata db-migrate`
- `strata index`
- `strata refresh`
- `strata search`
- `strata semantic-refresh`
- `strata semantic-status`
- indexing triggered by `strata promote`
- database checks reported by `strata doctor`

Their JSON output includes `backend: sqlite|turso`. Unrelated command JSON remains unchanged.

Human status output names the backend in migration, semantic status, and doctor. Search result rows remain unchanged, while backend-specific errors always identify the failing backend.

While Turso remains experimental, migration, refresh, semantic status, and doctor show one concise warning and their JSON includes `experimental: true`. Normal search output does not repeat the warning.

The Turso backend must preserve the existing CLI contract:

- human and JSON output shapes
- full and target indexing
- stale-path removal
- metadata, links, and Markdown sections
- archived exclusion by default
- `--include-archived`
- `--paths-only`
- `--limit`
- `--refresh`
- weighted full-text ranking and useful snippets
- optional semantic refresh
- hybrid search and explicit FTS fallback when semantic search is unavailable

If Turso cannot initialize or execute a query, the command fails clearly and instructs the user to set `index.backend: sqlite` and run `strata refresh`.

After changing `index.backend`, `strata refresh` is the normal rebuild path. `strata db-migrate` may create and migrate an empty selected index, but search and status commands never trigger an implicit rebuild and report `run strata refresh` when the selected index is missing.

`strata doctor` validates the active backend as required health state. It may report whether the inactive backend is compiled in, but it does not open, create, migrate, or rebuild the inactive backend's database.

Inactive index files remain untouched. Doctor may report their path, size, and age as informational data, but Strata does not refresh or delete them automatically.

`strata db-migrate` keeps its current command name, applies only the active backend's migration set, and reports `backend`, `db`, and `applied` in JSON.

## Implementation Plan

Keep each PR independently testable. Do not begin the next backend checkpoint until the previous checkpoint passes its SQLite/Linux and applicable Apple Silicon contract tests.

Turso may be exercised internally by tests during intermediate PRs, but `index.backend: turso` is not exposed to normal commands until the complete indexing, search, semantic, status, and failure contract is implemented.

### PR 1: Apple Silicon macOS support

1. Detect Darwin and `arm64` in `install.sh`.
2. Always run `cargo build --release` through one shared Linux/Apple Silicon path before installing; rely on Cargo incremental builds rather than trusting an existing artifact.
3. Install the binary through the existing managed-file path.
4. When `STRATA_CARGO_OFFLINE=1`, pass Cargo `--offline`; do not vendor the Rust dependency graph.
5. Make platform checks and documentation distinguish supported Apple Silicon macOS from unsupported Intel macOS.
6. Run the existing fixture acceptance flow on Apple Silicon.
7. Add a native macOS ARM CI job when a runner is available; otherwise provide a repeatable local smoke script and record its results.

Exit criteria:

- `install.sh` installs a working locally built binary on Apple Silicon.
- Linux uses the same local Cargo build path, and missing Cargo produces a clear prerequisite error.
- The normal init, refresh, search, semantic, and doctor smoke flow passes.
- Validation executes natively on Apple Silicon; cross-compilation alone is insufficient.
- Existing Linux installation and tests remain unchanged.

### PR 2: Backend selection and SQLite preservation

1. Add an `index` section to `configs.yaml` and compiled config with `backend: sqlite|turso`.
2. Default missing configuration to `sqlite`.
3. Add `index.backend: sqlite` to new-vault templates without rewriting existing user-owned `configs.yaml`.
4. Resolve the active backend once per command before opening or migrating an index.
5. Add a minimal single-thread Tokio runtime at the Turso backend execution boundary without converting the synchronous CLI or filesystem pipeline to async.
6. Add one small operation-level backend module for migrate, index, search, semantic refresh, and semantic status; do not expose SQL connection or statement primitives to callers.
   Use the shallow layout `src/index/{mod.rs,model.rs,sqlite.rs,turso.rs}` and keep CLI output formatting in `main.rs`.
7. Keep current rusqlite behavior behind the SQLite backend.
8. Centralize backend path selection:
   - SQLite: `0_core/db/strata.db`
   - Turso: `0_core/db/strata-turso.db`
9. Reject unsupported backend values during config compilation.
10. Include the active backend and database path in relevant JSON status output and doctor output.
11. Preserve explicit freshness: only refresh/index and migration paths may create index state; search and status paths do not rebuild.
12. Build one CLI containing both backends; do not introduce backend-specific binaries or distributions.
13. Keep config validation platform-neutral; check backend runtime availability during command execution and doctor checks.
14. When compiled `index.backend` changes, warn that `strata refresh` may be required without touching either index database.

Exit criteria:

- Existing vaults continue using SQLite without config changes.
- Every index-related command consistently selects one backend.
- Switching the config never converts, copies, or silently reads the other backend.

### PR 3: Turso schema and indexing

1. Move existing SQLite behavior behind the new backend module and require all current tests to pass before adding Turso implementation.
2. Add an exact released version of the embedded Rust `turso` dependency without removing `rusqlite`, and commit the resulting `Cargo.lock`.
3. Move SQLite migrations under `src/db/sqlite/` and add Turso migrations under `src/db/turso/`; each backend embeds its own ordered SQL files without requiring matching migration numbers.
4. Implement full and target indexing against Turso.
5. Preserve transaction boundaries, stale-row cleanup, link extraction, and section extraction.
6. Extract backend-neutral document, section, link, embedding, and search-result data contracts.
7. Keep backend-specific SQL and row handling inside the backend implementation; keep Markdown parsing, filesystem traversal, and index-data construction shared.
8. Make `strata refresh` rebuild the selected Turso index from the vault.
9. Preserve single-process write semantics and return clear lock/busy errors for overlapping commands.

Exit criteria:

- Turso full and target indexing produce the same logical records as SQLite.
- Each backend reports and applies its own schema version while preserving equivalent logical capabilities.
- Repeated Turso rebuilds are deterministic and do not crash or corrupt the database.
- Overlapping write attempts fail clearly and leave the index valid.
- SQLite code and behavior remain available.
- Future Turso upgrades rerun the complete contract and evaluation suite.

### PR 4: Turso full-text and semantic search

1. Implement Turso full-text search using Turso's native FTS capability with behavior matching the SQLite contract.
2. Preserve filters, result limits, path-only output, ranking intent, snippets, and JSON fields.
3. Store semantic vectors in Turso's native vector representation.
4. Use Turso's exact cosine-distance operation for semantic candidates.
5. Preserve the current hybrid score contract and explicit fallback behavior.
6. Report actual vector capability in `strata semantic-status`.

Exit criteria:

- Contract tests pass against both backends.
- Turso search has no user-visible correctness regression against SQLite.
- Native Turso FTS gaps are recorded as evaluation failures rather than hidden behind a custom search implementation.
- No custom ANN implementation is added.

### PR 5: Evaluation and recommendation

1. Build representative temporary vault copies on Linux and Apple Silicon macOS.
2. Run deterministic correctness cases against both backends using a committed synthetic fixture.
   The fixture includes ten curated queries with expected top paths covering title, description, body, exact phrase, metadata filtering, archived exclusion, typo/no-match behavior, natural-language semantic retrieval, and mixed FTS/vector relevance.
3. With explicit approval, run scale benchmarks against a temporary private-vault copy.
4. Measure:
   - full refresh elapsed time
   - median FTS query latency
   - median hybrid query latency
   - index file size
   - repeated rebuild stability
   Use a small repository script that runs the real CLI. Search measurements discard one warm-up and record ten runs per query; refresh measurements discard one warm-up and record three runs. Report medians and minimum-to-maximum ranges.
5. Compare search relevance by observable results rather than exact numeric ranks:
   - the same top result for every curated query;
   - at least 80% overlap in the top ten;
   - equivalent filters, snippets, and output contracts.
6. Write only aggregate measurements and non-sensitive synthetic query details to the report; do not publish private vault content or sensitive query text.
7. Write the versioned report to `docs/evaluations/turso-v<version>.md` and update the short `docs/evaluations/turso-latest.md` pointer.
8. Leave `sqlite` as the default regardless of the result; changing the default requires a later explicit decision.

The report records the exact Turso version and ends with one explicit verdict:

- `promote-candidate`
- `continue-evaluation`
- `reject-for-now`

Every failed gate must be named. The verdict does not change the configured default.

If an upstream Turso limitation blocks a required contract, keep the shared requirement intact. A narrowly ignored Turso test must link the upstream issue and appear as a failed gate; unresolved contract gaps prohibit `promote-candidate`.

For a `reject-for-now` verdict, retain the opt-in backend only if it remains buildable and cheap to maintain. Otherwise remove its code and config option while retaining the evaluation report and decision history.

If a later build does not include a previously valid configured backend, recognize the value and return a clear unavailable-backend error with SQLite/refresh guidance; never reinterpret it silently.

Turso passes the replacement-candidate gate only when:

- there are no user-visible correctness regressions;
- curated queries have the same top result and at least 80% top-ten overlap;
- full refresh is no slower than 2× SQLite;
- median FTS query latency is no slower than 2× SQLite;
- median hybrid query latency is no slower than 2× SQLite; and
- the Turso index file is no larger than 2× the equivalent SQLite index; and
- repeated rebuilds show no crashes or database corruption.

## Test Matrix

| Area | SQLite/Linux | Turso/Linux | SQLite/Apple Silicon | Turso/Apple Silicon |
|---|---:|---:|---:|---:|
| Install and init | Required | Required | Required | Required |
| Full and target index | Required | Required | Required | Required |
| Stale-row cleanup | Required | Required | Required | Required |
| FTS ranking and snippets | Required | Required | Required | Required |
| Filters and JSON output | Required | Required | Required | Required |
| Semantic refresh/status | Required | Required | Required | Required |
| Hybrid search/fallback | Required | Required | Required | Required |
| Repeated rebuild stability | Required | Required | Required | Required |
| Interrupted refresh then rebuild | Required | Required | Required | Required |

Tests use committed synthetic fixture vaults or explicitly approved temporary copies of a real vault. They never modify the installed private vault, and reports from private-vault-copy benchmarks contain aggregate data only.

The matrix is implemented as one parameterized backend contract suite. Adapter-specific tests cover only backend migration syntax, native FTS/vector behavior, and lock/busy errors.

Recovery tests interrupt a refresh and then rerun it. The interrupted index need not remain queryable, but the rerun must restore a complete valid index without manual repair.

## Deferred

- Making Turso the default.
- Removing rusqlite or the SQLite backend.
- Turso Cloud and remote synchronization.
- Approximate vector indexes.
- Intel macOS.
- Homebrew, prebuilt binaries, signing, and notarization.
- Workflow runner and watcher work.

## Phase Exit

Phase 6 completes when Apple Silicon support is validated, SQLite remains healthy as the default, the Turso opt-in path and known gaps are documented, and the versioned evaluation report has an explicit verdict. Turso does not need to pass the replacement-candidate gates for the phase to complete.

## Outcome

The Turso 0.6.1 backend is functionally usable for indexing, full-text search, exact vector search, hybrid search, semantic refresh, and interrupted-refresh recovery. The core backend contract passed in Linux ARM64 and AMD64 containers and natively on Apple Silicon. It is not a replacement candidate because rebuild latency and index size remain materially worse than SQLite, including on a temporary copy of the private vault.

The phase verdict is `continue-evaluation`. SQLite remains the default; Turso remains experimental and opt-in. Re-evaluate after the first upstream stable release intended for production use. Any future promotion still requires an explicit decision and must pass the documented correctness, performance, size, and recovery gates.
