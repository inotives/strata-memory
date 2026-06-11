# Rust Runtime Migration Execution Plan

**Status:** Implemented  
**Updated:** 2026-06-11

This plan captures the agreed path from the Phase 4a Rust CLI baseline to a Rust-owned Strata-Memory runtime. It is a prerequisite track before implementing Phase 4 watchers and real-time sync from `docs/implementation_plan.md`.

## Current Baseline

- Rust CLI lives at `src/rust/strata`.
- The Rust CLI owns the runtime command surface listed in the watcher readiness gate below.
- `index` calls the internal Rust database migration helper before indexing.
- `db-migrate` is exposed as `strata db-migrate`.
- Runtime fixture tests target the Rust binary under `0_core/bin/strata`; `0_core/script` remains only for the one-off migration helper.
- Rust-specific tests cover the migrated runtime commands.
- Runtime logic is split across Rust modules instead of living in a single monolithic `main.rs`.

## Grill-Me Decisions

- Rust becomes the single product runtime.
- Shell scripts were temporary compatibility only during migration.
- After Rust owned the full runtime command set, deprecated shell scripts were deleted rather than archived.
- Existing command names should be preserved as `strata <command>` names.
- Machine contracts require strict parity:
  - JSON output for `--json`
  - exit codes
  - filesystem mutations
  - database mutations
- Human-readable text may improve and does not need byte-for-byte shell parity.
- Focused Rust dependencies are allowed when they replace runtime shell tooling or reduce parser risk.
- Expected dependency additions include `serde`, JSON/YAML support, and likely a real CLI parser such as `clap`.
- Validation should happen command by command with Rust parity tests before wrapper/deprecation cleanup.
- `install.sh` remains shell for now because it is repo installation glue, not vault runtime behavior.
- `migration.sh` is one-off legacy tooling and is not part of the Rust runtime migration focus.
- `migration.sh` is not a blocker for Phase 4 watchers.

## Scope

Runtime commands to migrate:

1. Bootstrap and indexing:
   - `init`
   - `db-migrate`
   - `config-compile`
   - `agents-generate`
   - existing `index`
   - existing `search`
   - existing `link-review`
2. Content lifecycle:
   - `normalize`
   - `promote`
   - `retention`
3. Health and review:
   - `doctor`
   - `tag-review`
   - `room-review`
   - `privacy-review`

Out of scope for this track:

- `migration.sh`, except for any later cleanup decision.
- Replacing `install.sh` with a Rust installer.
- Phase 4 watcher implementation itself.

## Execution Sequence

### Step 1: Refactor Rust CLI Modules

Goal: make the Rust command surface ready for more runtime behavior without growing a single monolithic `main.rs`.

Implementation steps:

1. Split argument parsing and command dispatch into `cli.rs`.
2. Move SQLite schema and migration behavior into `db.rs`.
3. Move indexing and search behavior into `index.rs` or separate `index.rs` and `search.rs` if cleaner.
4. Move link-review behavior into `review.rs`.
5. Add shared vault path helpers in `vault.rs`.
6. Keep existing behavior unchanged during the split.

Validation steps:

1. Run `cargo fmt --check`.
2. Run `cargo check`.
3. Run `cargo build --release`.
4. Run existing Rust tests for index, search, and link-review.
5. Run existing shell fixture tests to ensure wrappers still work.

Exit criteria:

- Existing Rust command behavior is unchanged.
- Existing test suite remains green.
- The codebase has clear module boundaries for the next command slice.

### Step 2: Bootstrap and Indexing Slice

Goal: make Rust own vault bootstrap and core generated runtime state.

Implementation steps:

1. Add `strata init`.
2. Expose existing migration helper as `strata db-migrate`.
3. Add `strata config-compile`.
4. Add `strata agents-generate`.
5. Keep `strata index`, `strata search`, and `strata link-review` stable.
6. Add focused dependencies for YAML/JSON parsing and CLI handling.
7. Remove runtime dependence on `jq`, `yq`, and external `sqlite3` for the migrated Rust commands where feasible.
8. Delete migrated shell runtime commands after Rust parity is complete.

Validation steps:

1. Add `test/rust_init_test.sh`.
2. Add `test/rust_db_migrate_test.sh`.
3. Add `test/rust_config_compile_test.sh`.
4. Add `test/rust_agents_generate_test.sh`.
5. Reuse the same fixture assertions as the shell tests.
6. Confirm installed runtime tests call `0_core/bin/strata`.
7. Run the full fixture suite.
8. Run cargo formatting, check, and release build.

Exit criteria:

- A fixture vault can be initialized, migrated, configured, generated, indexed, searched, and link-reviewed using Rust commands.
- JSON output and exit codes match the shell-era machine contract.
- Human-readable output is clear and does not need exact shell parity.

### Step 3: Content Lifecycle Slice

Goal: make Rust own the commands that mutate user Markdown lifecycle state.

Implementation steps:

1. Add `strata normalize`.
2. Add `strata promote`.
3. Add `strata retention`.
4. Reuse shared frontmatter, path, config, and indexing helpers from the Rust modules.
5. Ensure commands mutate Markdown/filesystem state first and then re-index affected paths.

Validation steps:

1. Add Rust parity tests matching the existing shell lifecycle tests.
2. Confirm durable-tier description validation.
3. Confirm promotion creates the durable target and archives the draft.
4. Confirm retention is report-only by default and deletes only with `--apply`.
5. Confirm failed operations preserve originals where the shell contract requires it.

Exit criteria:

- Draft normalization, promotion, archival, and retention are Rust-owned.
- Existing lifecycle fixture behavior remains covered by Rust tests.

### Step 4: Health and Review Slice

Goal: make Rust own vault health checks and non-link review commands.

Implementation steps:

1. Add `strata doctor`.
2. Add `strata tag-review`.
3. Add `strata room-review`.
4. Add `strata privacy-review`.
5. Share config and frontmatter parsing across review commands.

Validation steps:

1. Add Rust parity tests for doctor, tag review, room review, and privacy review.
2. Confirm `privacy-review` remains warning-only and exits successfully.
3. Confirm `doctor` reports blocking errors consistently.
4. Confirm review JSON shapes and exit codes match the machine contract.

Exit criteria:

- Runtime health and review workflows are Rust-owned.
- Phase 4 watcher implementation can depend on Rust commands only.

### Step 5: Shell Deprecation Cleanup

Goal: remove shell runtime command ownership after Rust parity is complete.

Implementation steps:

1. Update docs to present `strata` as the only runtime command surface.
2. Remove shell scripts that no longer provide runtime behavior.
3. Keep only installation glue that is intentionally still shell, such as `install.sh`.
4. Update tests so command behavior is asserted through Rust, not shell internals.
5. Remove shell-library tests that no longer map to active runtime behavior.
6. Leave `migration.sh` untouched unless a separate cleanup decision removes it.

Validation steps:

1. Run the full Rust command test suite.
2. Run install tests.
3. Run cargo formatting, check, and release build.
4. Confirm docs no longer instruct users to call shell runtime scripts.

Exit criteria:

- `strata` is the only supported runtime interface.
- Shell command implementations are deleted after replacement.
- Phase 4 watcher work can proceed against a Rust-owned runtime.

## Phase 4 Watcher Readiness Gate

Before starting watcher implementation, the following Rust commands should be available and tested:

- `strata init`
- `strata db-migrate`
- `strata config-compile`
- `strata agents-generate`
- `strata index`
- `strata search`
- `strata link-review`
- `strata normalize`
- `strata promote`
- `strata retention`
- `strata doctor`
- `strata tag-review`
- `strata room-review`
- `strata privacy-review`

`migration.sh` is explicitly not part of this readiness gate.
