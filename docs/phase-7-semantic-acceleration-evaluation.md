# Phase 7: Semantic Search Acceleration Evaluation

## Goal

Determine whether Strata's exact Rust semantic search needs an approximate nearest-neighbor acceleration cache, and implement HNSW only when measured latency justifies the added lifecycle complexity.

## Confirmed Decisions

- SQLite remains the default and authoritative index database.
- Stored SQLite embedding BLOBs remain the authoritative semantic data.
- Exact Rust semantic search remains the baseline.
- HNSW is benchmark-gated, not guaranteed phase scope.
- Benchmark semantic vector ranking and complete hybrid search separately.
- The HNSW implementation trigger is semantic vector ranking above 100 ms p95 on supported hardware at a documented dataset size.
- Complete hybrid search has a 150 ms p95 target but does not independently trigger HNSW.
- Performance gates run on native Apple Silicon, native Linux ARM64 when available, and native Linux AMD64 CI.
- Emulated Linux validates correctness only.
- Exceeding the semantic ranking trigger on any supported native platform is sufficient to implement HNSW.
- Benchmark 25K embeddings as the current scale, 100K as the expected scale, and 500K as capacity planning.
- Only failures at 25K or 100K trigger HNSW; 500K results do not.
- Run both the current 64-dimensional embeddings and a future-facing 384-dimensional case.
- Use 100 deterministic queries per dataset, discard one warm-up, and record 20 measured runs per query.
- Generate normalized clustered synthetic vectors with fixed seeds so performance runs are reproducible and nearest-neighbor relevance is measurable.
- An approved temporary private-vault copy may provide supplemental scale evidence; never commit its vectors or query text.
- Reports contain only aggregate latency, recall, memory, startup, and disk-size results.
- Test wrong dimensions, zero vectors, corrupt BLOBs, and NaN values separately from performance benchmarks.
- Prefer `hnsw_rs` as the HNSW implementation, currently evaluating release `0.3.4`.
- Final crate selection requires a compatibility spike covering stable Rust, Apple Silicon, Linux ARM64, Linux AMD64, cosine distance, filtering, and dump/reload.
- Pin the accepted crate version exactly and leave optional SIMD features disabled by default.
- Persist the graph at `0_core/cache/semantic/sqlite-hnsw-<provider>-<model>-<dimension>.hnsw`.
- Persist a sibling JSON manifest containing freshness identity, HNSW parameters, vector count, and cache format version.
- Keep semantic acceleration artifacts under `0_core/cache/semantic/`, never under `0_core/db/`.
- Define freshness with the cache format version, SQLite backend, provider, model, embedding dimension, embedding count, HNSW parameters, crate version, and a deterministic digest over ordered `(path, target_type, section_start_line, content_hash)` records.
- Do not use database mtime or file size as freshness evidence.
- Missing, stale, incompatible, or unreadable HNSW artifacts fall back to exact semantic search.
- Search never rebuilds HNSW automatically; `strata semantic-refresh` owns cache rebuilding.
- The first implementation rebuilds all embeddings and then rebuilds the complete HNSW cache.
- Do not implement incremental HNSW insertion, update, or deletion until full rebuild time is measured as a problem.
- Rebuild SQLite embeddings transactionally before publishing acceleration artifacts.
- Build graph and manifest into uniquely named temporary files, flush and close them, rename the graph into place, and rename the manifest last as the commit marker.
- Search trusts a graph only when the matching manifest validates.
- Remove abandoned temporary artifacts during the next `strata semantic-refresh`.
- If cache publication fails after SQLite commits, exact semantic search remains available from the new embeddings.
- Do not add a `semantic.engine` configuration option in the first implementation.
- Hybrid search uses valid HNSW automatically and exact semantic search otherwise.
- Normal fallback from HNSW to exact semantic search is silent in text output because semantic behavior remains available.
- JSON search output reports `semantic_engine: "hnsw"` or `"exact"`.
- `strata semantic-status` reports cache readiness and a stale or unavailable reason.
- HNSW unavailability never causes semantic search to degrade to FTS when exact embeddings remain usable.
- HNSW recall@10 must be at least 95% against exact search.
- HNSW must return the same top result as exact search for at least 95% of deterministic queries.
- Metadata, status, and archived-content filters must remain exact.
- HNSW semantic ranking must be at most 50 ms p95 and complete hybrid search at most 100 ms p95.
- Cache load/startup must be at most 100 ms p95 at 100K vectors.
- Peak memory must be at most three times raw vector bytes plus 100 MiB.
- Cache disk size must be at most three times the SQLite embedding BLOB size.
- Full HNSW rebuild time must be at most twice embedding generation time.
- Failure of any gate prevents automatic HNSW use; exact search remains the production path.
- Apply archive and status eligibility during HNSW traversal using crate filter support, not only after retrieval.
- Map HNSW integer IDs to immutable embedding metadata loaded from authoritative SQLite records.
- Over-fetch at `limit × 4`, with a minimum of 50 candidates, matching current hybrid behavior.
- Deduplicate description and section embeddings to the best candidate per document path.
- Preserve current FTS/vector hybrid merge weights during the first HNSW evaluation.
- Assign sequential `u64` graph IDs from the deterministic ordered embedding records.
- Never use SQLite row IDs for graph identity.
- Store the ordered ID mapping in inspectable JSON with path, target type, section line, content hash, provider, and model.
- Graph IDs are stable only within one validated graph/manifest pair; a later rebuild may reassign them.
- Replace the JSON mapping with a binary format only if it causes the 100 ms startup gate to fail.
- HNSW acceleration applies only to the SQLite backend.
- Turso retains its native vector search path and remains outside the Phase 7 acceleration design.
- Do not add a cross-backend HNSW abstraction or a new index backend.
- Do not expose HNSW tuning as user configuration initially.
- Benchmark `M` values 16, 24, and 32; `ef_construction` values 100, 200, and 400; and `ef_search` values 50, 100, and 200.
- Select one parameter set per embedding dimension and prefer the smallest set that passes every promotion gate.
- Record selected parameters in the cache manifest and evaluation report.
- Any parameter change invalidates the cache.
- Phase 7 verdicts are `exact-sufficient`, `implement-hnsw`, or `continue-evaluation`.
- If exact search stays within the trigger gates, do not add `hnsw_rs` to production dependencies.
- An `exact-sufficient` result still commits the benchmark harness and synthetic datasets, publishes a versioned evaluation report, records the measured capacity ceiling, and defines the rerun trigger.
- Phase 7 may complete without changing SQLite semantic search.
- Rerun the evaluation when a real vault exceeds the recorded embedding-count ceiling, embedding dimension changes, provider/model changes, observed semantic ranking exceeds 100 ms p95, supported hardware changes materially, the preferred HNSW crate has a meaningful stable release, or exact-search implementation changes.
- Do not collect background latency telemetry.
- Performance measurement runs only through an explicit local benchmark command.
- Implement the first benchmark as a repository evaluation script, not a production `strata` command.
- Synthetic matrix mode is the default.
- Real-vault benchmarking requires an explicit temporary copy path and rejects the active installed vault unless an override is deliberately supplied.
- The benchmark is read-only except for temporary output under `test/tmp/` or an explicitly supplied report path.
- Promote the benchmark into the production CLI only if recurring user workflows justify it.
- Implement benchmark logic as a non-installed Rust binary in the existing `strata` crate.
- Run it with `cargo run --release --manifest-path src/rust/strata/Cargo.toml --bin semantic-benchmark -- ...`.
- Reuse production vector decoding, cosine ranking, filtering, and candidate logic in-process.
- A thin shell wrapper may simplify matrix execution, but Python does not implement or time the vector search.
- Extract a focused `src/index/semantic.rs` module before benchmarking.
- The module owns vector encoding/decoding, cosine similarity, exact candidate ranking, per-path deduplication, and later exact/HNSW engine selection.
- SQLite remains responsible for loading authoritative embedding rows and metadata.
- Turso keeps its native vector-search path and does not use the new semantic engine seam.
- Do not introduce a broader semantic framework or cross-backend interface.
- Add a crate library target so the installed CLI and non-installed semantic benchmark share production modules.
- Move the current CLI entry point to `src/bin/strata.rs`, add `src/bin/semantic-benchmark.rs`, and expose shared modules through `src/lib.rs`.
- Do not duplicate modules with `#[path]` or maintain separate benchmark implementations.
- Implement Phase 7 through separate gated checkpoints:
  1. Add the library target with no behavior change and rerun the full existing test matrix.
  2. Extract `semantic.rs` and prove exact-search parity.
  3. Add the benchmark binary and publish baseline results.
  4. Begin the HNSW compatibility spike only when baseline results trigger it.
- Do not mix structural refactoring, baseline measurement, and HNSW implementation in one checkpoint.
- The `semantic.rs` extraction must preserve candidate paths and order.
- Cosine scores must remain equal within `1e-6`.
- The same best description or section embedding must be selected per document path.
- Archive filtering, hybrid result order, warnings, and JSON output contracts must remain unchanged.
- Empty, zero, corrupt, NaN, and dimension-mismatched vectors require explicit deterministic behavior.
- Exact-ranking latency at 25K vectors may not regress by more than 5% after extraction.
- Skip and count vectors with wrong byte length, decoded dimension mismatch, NaN, or infinite components.
- Permit zero vectors and score them as `0.0`.
- Continue semantic search with remaining valid vectors and report skipped-vector counts in JSON and semantic status.
- `strata semantic-refresh` must never write malformed vectors.
- If no eligible valid vectors remain, hybrid search explicitly falls back to FTS.
- Load and validate the HNSW cache lazily on the first semantic query in a process.
- Retain a process-local cache keyed by the validated cache identity.
- Key the process-local cache by canonical vault path plus the complete manifest identity.
- Retain at most one loaded semantic acceleration cache per vault; replace it when identity changes.
- Do not add a daemon, background service, or shared-memory cache.
- Add `0_core/cache/semantic/` to the managed vault `.gitignore`.
- Installer creates the cache directory but never ships graph, mapping, manifest, or temporary artifacts.
- Vault backups and restores may omit semantic acceleration artifacts safely.
- After restore, exact semantic search works immediately and `strata semantic-refresh` rebuilds HNSW.
- Preserve current single-writer SQLite transaction semantics for embedding refresh.
- Use a per-vault semantic-build lock file under `0_core/tmp/`.
- Search may use the last published cache while its manifest still matches authoritative embeddings.
- After new embeddings commit, the old cache is stale; search uses exact semantic ranking until the new manifest publishes.
- A concurrent second `semantic-refresh` fails clearly rather than waiting indefinitely.
- Lock files record process ID and timestamp; stale locks are cleared only when the recorded process no longer exists.
- Use a fixed graph-construction seed in benchmarks, tests, and production.
- Record the seed and crate version in the cache manifest.
- Do not require byte-identical graph files across architectures or crate versions.
- Require validated manifest identity and quality gates rather than graph-byte equality.
- Do not guarantee semantic acceleration cache portability across operating systems or architectures.
- Record OS, architecture, endianness, pointer width, Rust target triple, crate version, and cache format version in the manifest.
- A platform mismatch marks the cache incompatible; exact search continues until local `semantic-refresh` rebuilds it.
- Do not add application-level encryption for semantic acceleration artifacts in Phase 7.
- Rely on vault filesystem or full-disk encryption and normal access controls.
- Create cache artifacts with owner-only permissions where the platform supports them.
- Keep vectors out of the JSON mapping and minimize stored metadata.
- Document graph, mapping, and manifest files as sensitive disposable data.
- Preserve existing `semantic-status` fields for backward compatibility.
- Add `semantic_engine` and a nested `hnsw` status object containing enabled, ready, reason, vector count, cache format, crate version, and build time.
- Use stable HNSW reason codes: `not_triggered`, `missing`, `stale`, `incompatible`, `corrupt`, `building`, `ready`, and `gates_failed`.
- Human-readable `semantic-status` shows provider, model, embedding count, selected semantic engine, and a concise HNSW cache state.
- Do not print HNSW tuning parameters in normal text output; keep implementation details in JSON.
- Publish the exact baseline as `docs/evaluations/semantic-exact-v1.md`.
- If HNSW is triggered, publish its evaluation separately as `docs/evaluations/semantic-hnsw-v1.md`.
- Maintain `docs/evaluations/semantic-latest.md` as the current verdict pointer.
- Reports record Git commit, platform, hardware, Rust version, crate version, HNSW parameters, dataset seed, dimensions, vector counts, latency distributions, recall, memory, disk size, startup, rebuild time, failed gates, and verdict.
- Benchmark cold cache load and warm semantic-query latency separately.
- Require library-refactor parity and exact benchmark correctness on Apple Silicon macOS, Linux ARM64, and Linux AMD64.
- Require native performance evidence on Apple Silicon and Linux AMD64.
- Native Linux ARM64 performance may remain pending when no native runner is available, but correctness is required.
- If HNSW is triggered, require build, load, search, interruption recovery, and cross-platform cache rejection tests on every supported platform.
- Emulated runs provide optional correctness evidence only.
- A future long-running workflow process may naturally reuse the same process-local cache.
- Any HNSW structure is disposable derived state, not an index backend.
- Semantic acceleration is Phase 7. Workflow automation and watchers move to Phases 8 and 9.

## Implementation Plan

### Checkpoint 1: Shared Rust library

1. Add `src/lib.rs`.
2. Move the installed CLI entry point to `src/bin/strata.rs`.
3. Expose only the modules needed by the CLI and benchmark.
4. Preserve the installed binary name and every existing command/output contract.
5. Run the complete SQLite, Turso, Apple Silicon, and Linux correctness suites before continuing.

Exit: no user-visible behavior or performance change.

### Checkpoint 2: Exact semantic module

1. Add `src/index/semantic.rs`.
2. Move vector encoding/decoding, validation, cosine similarity, exact ranking, and per-path deduplication into it.
3. Keep SQLite row loading and metadata joins in `index/sqlite.rs`.
4. Add deterministic malformed-vector handling and skipped-vector reporting.
5. Prove result, score, filtering, hybrid-order, warning, and JSON parity.
6. Confirm exact ranking at 25K vectors regresses by no more than 5%.

Exit: the existing exact semantic engine is behaviorally equivalent and directly benchmarkable.

### Checkpoint 3: Exact-search benchmark

1. Add non-installed `src/bin/semantic-benchmark.rs`.
2. Add fixed-seed clustered synthetic generators for 25K, 100K, and 500K vectors at 64 and 384 dimensions.
3. Add 100 deterministic queries per dataset.
4. Discard one warm-up and record 20 runs per query.
5. Measure semantic ranking and complete hybrid search separately.
6. Record cold startup, warm latency, peak memory, raw vector bytes, and SQLite embedding size.
7. Run correctness on all supported platforms and native performance on Apple Silicon and Linux AMD64.
8. Publish `docs/evaluations/semantic-exact-v1.md` and update `semantic-latest.md`.

Exit:

- `exact-sufficient` when 25K and 100K semantic ranking stay at or below 100 ms p95.
- `implement-hnsw` when either trigger scale exceeds 100 ms p95 on any supported native platform.
- `continue-evaluation` only when required native evidence is unavailable or inconclusive.

### Checkpoint 4: Conditional HNSW spike

Run only for an `implement-hnsw` verdict.

1. Add exactly pinned `hnsw_rs` only after the compatibility spike passes.
2. Verify stable Rust, cosine distance, filtering, fixed-seed construction, dump/reload, and supported platforms.
3. Benchmark the documented parameter matrix and select the smallest passing set per dimension.
4. Implement manifest identity, sequential graph IDs, JSON metadata mapping, platform compatibility checks, and lazy process-local loading.
5. Integrate filtered HNSW ranking behind automatic exact fallback without changing hybrid weights.
6. Extend JSON search output and semantic status while preserving existing fields.

Exit: the spike can build, persist, reload, filter, and search deterministically on every supported correctness platform.

### Checkpoint 5: Conditional production cache lifecycle

Run only after the HNSW spike passes.

1. Create `0_core/cache/semantic/` and managed ignore rules.
2. Rebuild complete embeddings and HNSW through `semantic-refresh`.
3. Add the per-vault build lock and stale-lock recovery.
4. Publish graph, mapping, and manifest atomically with the manifest last.
5. Fall back to exact search for missing, stale, incompatible, corrupt, building, or gate-failed caches.
6. Add interruption, abandoned-temporary-file, permission, restore, and cross-platform rejection tests.
7. Run all promotion gates and publish `semantic-hnsw-v1.md`.

Exit: automatic HNSW use is enabled only if every promotion gate passes.

## Required Test Matrix

| Area | macOS ARM64 | Linux ARM64 | Linux AMD64 |
|---|---:|---:|---:|
| Library refactor parity | Required | Required | Required |
| Exact semantic parity | Required | Required | Required |
| Exact benchmark correctness | Required | Required | Required |
| Exact performance evidence | Native | Native when available | Native |
| Malformed-vector behavior | Required | Required | Required |
| HNSW build/load/search | If triggered | If triggered | If triggered |
| Filter and dedup parity | If triggered | If triggered | If triggered |
| Atomic publication recovery | If triggered | If triggered | If triggered |
| Platform-cache rejection | If triggered | If triggered | If triggered |

## HNSW Promotion Gates

- Recall@10 is at least 95%.
- The same top result is returned for at least 95% of deterministic queries.
- Metadata, status, and archive filtering remain exact.
- Semantic ranking is at most 50 ms p95.
- Complete hybrid search is at most 100 ms p95.
- Cold cache load is at most 100 ms p95 at 100K vectors.
- Peak memory is at most three times raw vector bytes plus 100 MiB.
- Cache disk size is at most three times SQLite embedding BLOB size.
- Full graph rebuild is at most twice embedding generation time.
- All existing SQLite, Turso, installer, doctor, search, and semantic contracts pass.

## Phase Exit

Phase 7 completes with one explicit verdict:

- `exact-sufficient`: retain exact Rust search and no production HNSW dependency.
- `implement-hnsw`: ship automatic HNSW acceleration only after every gate passes.
- `continue-evaluation`: retain exact search and document missing evidence or unresolved gaps.

Every verdict preserves SQLite embeddings as authoritative, SQLite as the default backend, and exact semantic search as the safe fallback.
