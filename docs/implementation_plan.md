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
2. Implement `init.sh` to create vault structure and bootstrap config.
3. Implement `config-compile.sh` using `yq` and `jq` for full mode.
4. Implement `db-migrate.sh` and initial schema migration.
5. Implement `normalize.sh` for constrained YAML frontmatter.
6. Implement `index.sh` for full scan and target indexing.
7. Implement FTS5 search, link extraction, section extraction, and stale row cleanup.
8. Implement `search.sh` with weighted ranking, snippets, filters, and `--json`.
9. Implement `tag-review.sh`, `room-review.sh`, and `link-review.sh`.
10. Implement `promote.sh` with vault-local temp handling, archival, no overwrite, and re-indexing.
11. Implement `agents-generate.sh` from templates/profiles/manual blocks.
12. Implement `doctor.sh`.
13. Implement `retention.sh` report mode and `--apply`.
14. Implement warning-only `privacy-review.sh`.

Testing steps:

1. `init.sh` creates expected folders and DB schema in fixture vault.
2. `config-compile.sh` validates nested rooms/profiles/tags and writes cache.
3. `normalize.sh` handles:
   - missing frontmatter
   - partial frontmatter
   - quoted timestamps
   - empty draft descriptions
   - missing durable descriptions as validation errors
4. `index.sh` handles:
   - target indexing
   - full scan
   - FTS rows
   - link rows
   - section rows
   - stale path removal
   - archived exclusion by default
5. `search.sh` verifies:
   - title matches rank above body matches
   - snippets are compact
   - `--json` is valid JSON
   - `--include-archived` works
   - `--paths-only` works
6. `tag-review.sh` detects similar tags.
7. `room-review.sh` flags unregistered rooms and respects recursive roots.
8. `link-review.sh` blocks broken durable links and warns in drafts.
9. `promote.sh` verifies:
   - target creation
   - draft archival
   - original deletion after successful final writes
   - no overwrite by default
   - `--new-slug`
   - failed operations leave original intact when possible
10. `agents-generate.sh` preserves manual blocks and updates generated sections.
11. `doctor.sh` reports a healthy fixture vault.
12. `retention.sh` reports candidates without deleting by default and deletes only with `--apply`.
13. `privacy-review.sh` reports warnings without blocking.

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

1. Run `doctor.sh` against the migrated private vault.
2. Run `room-review.sh` and register approved rooms.
3. Run `tag-review.sh` and approve replacements/new tags.
4. Run `link-review.sh` and fix broken local links.
5. Review `_unmapped` content and move/register it.
6. Run `privacy-review.sh`.
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
- Watcher work may start only after this phase is accepted.

## Phase 4: Watchers and Real-Time Sync

Goal: automate indexing after external file edits.

Implementation steps:

1. Add watcher design doc based on stable migration/index behavior.
2. Implement `watcher/linux.sh` first.
3. Add event debounce and duplicate-event handling.
4. Use content hash and modified fields to avoid unnecessary re-indexing.
5. Add post-MVP `watcher/mac.sh` when macOS validation is available.

Testing steps:

1. Linux fixture watcher detects creates, edits, moves, and deletes.
2. Watcher does not index ignored paths.
3. Watcher handles rapid consecutive writes.
4. Watcher recovery works after restart.

Exit criteria:

- Linux watcher is reliable against migrated vault fixtures.
- macOS remains deferred until available hardware.

## Phase 5: Semantic and Vector Search

Goal: add optional semantic retrieval after lifecycle/search correctness is stable.

Implementation steps:

1. Choose embedding install path and model management.
2. Add optional `sqlite-vec` support.
3. Add embedding table keyed by content hash.
4. Start with description embeddings.
5. Later add section/body chunk embeddings.
6. Add hybrid FTS/vector search mode.

Testing steps:

1. Missing vector dependencies degrade cleanly to FTS.
2. Embeddings are invalidated by content hash changes.
3. Hybrid search preserves metadata/status filters.

Exit criteria:

- Vector search is optional and cannot break core FTS workflows.

## Phase 6: Workflow Runner and Richer Automation

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
