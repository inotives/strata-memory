# Strata-Memory Implementation Plan

**Status:** Draft  
**Updated:** 2026-06-06

This plan breaks implementation into phases with concrete build steps and testing gates. It intentionally stops at planning; no implementation should start until this plan is reviewed.

## Phase 0: Public Engine Repo Foundation

Goal: make the public repo a clean engine project that can install managed files into a private vault.

Implementation steps:

1. Create public repo layout: `src/`, `src/script/`, `src/script/lib/`, `src/template/`, `src/db/`, `src/doc/`, `example/`, `test/`.
2. Move engine-facing docs/templates into `src/` while keeping `docs/project_spec.md` and public planning docs in `docs/`.
3. Treat `docs/AGENTS_template.md` as the public starter for the private vault prompt until the managed template tree exists under `src/template/`.
4. Add `install.sh` that copies managed files from `src/` into `${STRATA_VAULT:-$HOME/.strata-memory}/0_core/`.
5. Add `manifest.json` generation for managed files.
6. Add default `.gitignore` template for the private vault.
7. Add dependency detection helpers for bootstrap and full mode.

Testing steps:

1. Run install into an isolated fixture vault under the repo test temp directory.
2. Assert managed files exist in `0_core/`.
3. Assert `configs.yaml` is preserved on reinstall.
4. Assert untracked user files are not overwritten.
5. Assert missing dependencies produce clear messages.

Exit criteria:

- Install into an empty fixture vault is repeatable.
- Reinstall updates managed files without touching user-owned config/content.

## Phase 1: Empty Strata Vault MVP

Goal: operate a new empty Strata vault end to end without migration.

Implementation steps:

1. Implement shared Bash 3.2-compatible libraries:
   - `config.sh`
   - `frontmatter.sh`
   - `json.sh`
   - `paths.sh`
   - `platform.sh`
   - `sqlite.sh`
   - `log.sh`
2. Implement `strata init` to create vault structure and bootstrap config.
3. Implement `strata config-compile` in Rust.
4. Implement `strata db-migrate` and initial schema migration.
5. Implement `strata normalize` for constrained YAML frontmatter.
6. Implement `strata index` for full scan and target indexing.
7. Implement FTS5 search, link extraction, section extraction, and stale row cleanup.
8. Implement `strata search` with weighted ranking, snippets, filters, and `--json`.
9. Implement `strata tag-review`, `strata room-review`, and `strata link-review`.
10. Implement `strata promote` with vault-local temp handling, archival, no overwrite, and re-indexing.
11. Implement `strata agents-generate` from templates/profiles/manual blocks.
12. Implement `strata doctor`.
13. Implement `strata retention` report mode and `--apply`.
14. Implement warning-only `strata privacy-review`.

Testing steps:

1. `strata init` creates expected folders and DB schema in fixture vault.
2. `strata config-compile` validates nested rooms/profiles/tags and writes cache.
3. `strata normalize` handles:
   - missing frontmatter
   - partial frontmatter
   - quoted timestamps
   - empty draft descriptions
   - missing durable descriptions as validation errors
4. `strata index` handles:
   - target indexing
   - full scan
   - FTS rows
   - link rows
   - section rows
   - stale path removal
   - archived exclusion by default
5. `strata search` verifies:
   - title matches rank above body matches
   - snippets are compact
   - `--json` is valid JSON
   - `--include-archived` works
   - `--paths-only` works
6. `strata tag-review` detects similar tags.
7. `strata room-review` flags unregistered rooms and respects recursive roots.
8. `strata link-review` blocks broken durable links and warns in drafts.
9. `strata promote` verifies:
   - target creation
   - draft archival
   - original deletion after successful final writes
   - no overwrite by default
   - `--new-slug`
   - failed operations leave original intact when possible
10. `strata agents-generate` preserves manual blocks and updates generated sections.
11. `strata doctor` reports a healthy fixture vault.
12. `strata retention` reports candidates without deleting by default and deletes only with `--apply`.
13. `strata privacy-review` reports warnings without blocking.

Exit criteria:

- The Linux MVP acceptance flow passes in an isolated fixture vault.
- No test touches `~/.strata-memory` or `~/.agent-knowledge`.

## Phase 2: Section Migration

Goal: migrate selected sections from old Agent Memory into the new vault without modifying the old memory.

Implementation steps:

1. Implement `migration.sh` section flags:
   - `config`
   - `knowledge`
   - `intelligence`
   - `agents-md`
   - `all`
2. Implement read-only source checks for `~/.agent-knowledge/memory`.
3. Implement canonical path mapping from plural legacy names to singular Strata names.
4. Skip old drafts entirely.
5. Lowercase and hyphen-normalize target paths.
6. Preserve display casing in metadata.
7. Detect target path collisions before writing.
8. Rewrite deterministic links:
   - old absolute paths under old vault root
   - unambiguous wikilinks
9. Flag ambiguous/unresolved links in reports.
10. Place unmatched knowledge under `2_knowledge/_unmapped/`.
11. Write section migration reports under `3_intelligence/report/migration/`.
12. Re-index migrated target files.

Testing steps:

1. Build a fixture old Agent Memory tree with:
   - known rooms
   - unknown rooms
   - mixed casing
   - wikilinks
   - absolute old-vault links
   - path collisions
   - drafts that must be skipped
2. Assert old fixture tree is byte-for-byte unchanged after migration.
3. Assert each section can be rerun idempotently.
4. Assert collisions block by default.
5. Assert unmapped files are preserved under `_unmapped`.
6. Assert migration reports include mapped, unmapped, skipped, rewritten, and warning records.
7. Assert migrated vault indexes and searches successfully.

Exit criteria:

- Section migration runs safely and repeatably against fixtures.
- No migration path modifies or deletes old Agent Memory content.

## Phase 3: Migration Validation and Cleanup

Goal: stabilize the migrated private vault before adding background automation.

Implementation steps:

1. Run `strata doctor` against the migrated private vault.
2. Run `strata room-review` and register approved rooms.
3. Run `strata tag-review` and approve replacements/new tags.
4. Run `strata link-review` and fix broken local links.
5. Review `_unmapped` content and move/register it.
6. Run `strata privacy-review`.
7. Generate final `AGENTS.md`.
8. Run full re-index.
9. Create a migration validation report.

Testing steps:

1. Fixture validation flow resolves unknown tags and rooms.
2. Verify generated `AGENTS.md` reflects final profile rooms and commands.
3. Verify search defaults exclude archived drafts and include generated reports.
4. Verify retention report does not delete unless `--apply`.

Exit criteria:

- Migrated vault has no blocking doctor errors.
- `_unmapped` has been reviewed or intentionally retained.
- Search freshness work may start only after this phase is accepted.

## Phase 4: Search Freshness Policy

Goal: keep search fast by default while giving humans and agents explicit controls to refresh the derived SQLite index when freshness matters.

Implementation steps:

1. Add `strata refresh` as a top-level command that runs the same full-index path as `strata index --full`.
2. Add `strata refresh --json` with output shaped like `{"ok":true,"indexed":N}`.
3. Add `strata search --refresh` to run a full refresh before executing the search query.
4. Keep plain `strata search` fast by querying the existing index without implicit re-indexing.
5. Keep refresh/index progress and status on stderr so stdout remains parseable search output.
6. For `strata search --refresh --json`, include refresh metadata such as `refreshed: true` and `indexed: N`.
7. For plain `strata search --json`, include `refreshed: false`.
8. Improve missing-database search errors to suggest `strata refresh`.
9. Update generated `AGENTS.md` guidance to run `strata refresh` once per session and again after creating, editing, moving, deleting, promoting, or migrating vault files.
10. Document that `strata refresh` only updates the derived index and runs existing DB migrations; health and review commands remain separate.

Testing steps:

1. `strata refresh` indexes an isolated fixture vault and updates stale rows.
2. `strata refresh --json` emits valid JSON with the indexed count.
3. `strata search --refresh` returns fresh results after an external file edit.
4. `strata search --refresh --json` emits one parseable JSON object containing refresh metadata and results.
5. Plain `strata search` does not run a refresh implicitly.
6. Missing-database search errors recommend `strata refresh`.
7. Generated `AGENTS.md` includes the session refresh guidance.

Exit criteria:

- Agents and humans have a documented, explicit refresh path before memory lookup.
- Repeated plain searches remain fast because they do not re-index by default.

## Phase 5: Semantic and Vector Search

Goal: add optional local semantic retrieval after lifecycle/search correctness is stable, without weakening FTS5 reliability or the local-first privacy model.

Design decisions:

1. Semantic search is optional; FTS5 search must continue working when semantic dependencies are missing.
2. The first implementation is local-only. Do not send vault content to hosted/API embedding providers.
3. Store semantic metadata in `0_core/db/strata.db` so the derived search index remains inspectable and rebuildable.
4. Embed frontmatter descriptions and Markdown sections first; do not start with whole-file embeddings.
5. Plain `strata search` remains FTS5-only by default.
6. `strata search --hybrid` is opt-in.
7. If hybrid search is requested but semantic search is unavailable, return FTS5 results with an explicit warning.
8. JSON output includes requested mode, actual mode, and warnings.
9. Use `strata semantic-status` as the user-facing status command.
10. Split implementation into a foundation PR and a provider PR.

### Phase 5 PR 1: Semantic Search Foundation

Implementation steps:

1. Add schema migrations for semantic metadata and vector index readiness.
2. Track provider, model, embedding dimension, path, section identity, and content hash.
3. Add config fields for semantic search provider/model without requiring them.
4. Add `strata semantic-status` with human and JSON output.
5. Add `strata search --hybrid`.
6. Keep hybrid fallback on FTS5 when no provider, no semantic index, or no vector extension is available.
7. Print human fallback warnings to stderr.
8. Include JSON fields such as `requested_mode`, `mode`, and `warnings`.
9. Do not generate embeddings in this PR.

Testing steps:

1. Missing semantic config reports semantic search unavailable while FTS5 remains available.
2. `strata semantic-status --json` reports provider configuration, vector index readiness, and fallback mode.
3. Plain `strata search` remains FTS5-only.
4. `strata search --hybrid` falls back to FTS5 with a human warning when semantic search is unavailable.
5. `strata search --hybrid --json` returns parseable JSON with requested mode, actual mode, warnings, and normal FTS results.
6. Existing search filters, archived exclusion, `--paths-only`, `--limit`, `--refresh`, and `--json` continue to work.

Exit criteria:

- The semantic search product contract is represented in schema, config, CLI, docs, and tests.
- No embedding runtime is required for the CLI or existing tests to pass.
- FTS5 behavior is unchanged unless `--hybrid` is explicitly requested.

### Phase 5 PR 2: First Local Embedding Provider

Implementation steps:

1. Use the built-in local hash embedding runtime first (`builtin-hash` / `hash-v1`) so the feature has no hosted API, model download, or external daemon requirement.
2. Add `strata semantic-refresh` as the embedding refresh command.
3. Embed non-empty frontmatter descriptions.
4. Embed Markdown sections from the existing `sections` table.
5. Key embeddings by content hash and model identity so stale vectors can be rebuilt.
6. Add local vector nearest-neighbor search in the CLI; keep external vector extensions such as `sqlite-vec` optional future improvements.
7. Combine FTS and vector scores for hybrid ranking.
8. Keep vectors local and rebuildable from Markdown.

Testing steps:

1. Missing vector dependencies degrade cleanly to FTS.
2. Embeddings are invalidated by content hash changes.
3. Hybrid search preserves metadata/status filters.
4. Empty descriptions are skipped.
5. Archived content remains excluded by default.
6. Live validation runs against a temporary or approved real-vault copy.

Exit criteria:

- Vector search is optional and cannot break core FTS workflows.
- Hybrid search improves natural-language discovery without weakening exact FTS matches.

## Phase 6: Apple Silicon macOS and Turso Index Backend Evaluation

Goal: support local installation on Apple Silicon macOS and determine whether embedded local Turso can eventually replace SQLite without changing the production default.

Reference: `docs/_archived/phase-6-macos-turso-evaluation.md`

Implementation steps:

1. Add Apple Silicon detection, local release build, installation, and smoke validation to the existing installer.
2. Add vault-wide `index.backend: sqlite|turso`, defaulting to `sqlite`.
3. Keep separate rebuildable database files for SQLite and Turso.
4. Preserve the current SQLite/rusqlite backend.
5. Implement Turso as an opt-in complete backend for migrations, indexing, FTS, semantic vectors, hybrid search, status, and doctor checks.
6. Use Turso exact vector distance functions; do not build a custom ANN index.
7. Run cross-backend correctness, stability, size, and latency comparisons on Linux and Apple Silicon macOS.
8. Publish an evaluation report without changing the default backend.

Testing steps:

1. Existing vaults remain on SQLite when `index.backend` is absent.
2. Every index-related command uses the configured backend consistently.
3. Both backends pass the same CLI contract tests.
4. Backend switching requires `strata refresh` and never converts or silently falls back.
5. Apple Silicon installation and the normal acceptance flow pass.
6. Turso meets or fails the documented replacement-candidate gates with recorded evidence.

Exit criteria:

- Apple Silicon macOS is a supported local-build platform.
- Turso is a complete opt-in backend with measured parity and reliability results.
- SQLite remains the default and available fallback.

## Phase 7: Workflow Runner and Richer Automation

Goal: execute workflow definitions with dependency checks and report generation.

Implementation steps:

1. Define workflow execution contract.
2. Validate `required_skills` and `required_agents`.
3. Enforce skill script allowlist.
4. Add run logs under `3_intelligence/report/`.
5. Add profile/domain workflows such as trader research flows.

Testing steps:

1. Missing dependencies fail before execution.
2. Non-allowlisted scripts require approval or fail in noninteractive mode.
3. Workflow outputs are indexed as generated reports.
4. Workflow logs are searchable.

Exit criteria:

- Workflows run reproducibly without weakening script execution boundaries.

## Phase 8: Optional Watchers and Real-Time Sync

Goal: automate indexing after external file edits only if explicit refresh proves too manual.

Implementation steps:

1. Add watcher design doc based on stable migration/index behavior and the Phase 4 refresh contract.
2. Implement Linux watcher support first.
3. Add event debounce and duplicate-event handling.
4. Use content hash and modified fields to avoid unnecessary re-indexing.
5. Add Apple Silicon macOS watcher support when justified by refresh usage.

Testing steps:

1. Linux fixture watcher detects creates, edits, moves, and deletes.
2. Watcher does not index ignored paths.
3. Watcher handles rapid consecutive writes.
4. Watcher recovery works after restart.

Exit criteria:

- Linux watcher is reliable against migrated vault fixtures.
- Watchers remain optional on both supported platforms.
