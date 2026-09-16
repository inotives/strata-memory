# Promotion Archive ID-Collision Regression Plan

**Status:** Implemented in branch; live-binary deployment pending

## Diagnosis

The reported collision was reproducible in the historical shell-index flow,
but not in the current Rust CLI. A disposable vault using both the workspace
binary and the currently installed private-vault binary completed this flow:

1. Create a pending draft with `id: "promotion-collision"`.
2. Promote it to `2_knowledge`.
3. Retain the archived copy under `1_draft/_archived`.
4. Run a full `strata refresh`.

Both refreshes succeeded. Current promotion writes the archive with
`id: "promotion-collision_archived"`; the durable copy retains the logical
ID. Both SQLite and Turso remove stale paths before full-index inserts.

## New Evidence

The reported failing command exits nonzero after its file operations with
`UNIQUE constraint failed: memory_index.id`. The lifecycle promotion function
writes the promoted file, archive, and operation log; the CLI dispatcher then
indexes the target and archive. A disposable reproduction using a normal
promotion completed promotion and full refresh without an error.

The `strata` executable used by the failing session is therefore not the
current workspace command path observed here, or it is wrapped by additional
indexing behavior. Do not change the current promotion code until that
executable is identified.

## Resolved Source Defect

Promotion previously protected only the destination path. A second pending
draft with the same frontmatter ID but a different filename could therefore
write a second durable page and archive before the dispatcher's target-index
write failed on the duplicate ID.

The fix rejects an already-owned promoted document ID before either file is
written. Regression coverage proves the duplicate source remains in place and
neither a duplicate durable page nor archive is created. The SQLite promotion
test and Turso backend contract both pass with the guard. With `--json`, the
rejection emits `{"ok":false,"error":"duplicate_document_id"...}` on stdout
and exits nonzero.

## Deployment Plan

1. In the same terminal/session that fails, capture `type -a strata` and
   `shasum -a 256 "$(command -v strata)"`.
2. Compare that path and hash with
   `~/.strata-memory/0_core/bin/strata`; inspect any shell alias, function,
   wrapper, or alternate vault installation revealed by `type -a`.
3. Run the reported promotion fixture against the identified executable in an
   isolated vault. This is the required red regression command.
4. Replace the obsolete binary or wrapper with a build from this branch and
   verify the updated installed binary is the one on `PATH`.

After the executable mismatch is resolved, lock the current expected behavior
down with regression coverage:

1. Extend `test/rust_promote_test.sh` after the first successful promotion to
   run `strata refresh` and assert both the durable and archived paths remain
   indexed.
2. Query the SQLite fixture index to assert the durable record retains
   `mem_promote_001` and the archive record uses
   `mem_promote_001_archived`.
3. Extend `test/rust_index_backend_test.sh` with the same promote-and-refresh
   fixture while Turso is active, asserting both paths index successfully.
4. Do not alter frontmatter IDs during refresh and do not exclude archives
   from search. The archive-specific ID is created only by promotion, while
   archived records remain filterable by their `archived` status.

## Documentation Change

Add an **Update an existing vault** section to the README. It must instruct a
user to update their source checkout, rerun the installer against the existing
vault, and verify the installed binary directly:

```bash
git fetch origin
git switch <current-release-branch>
git pull --ff-only
./install.sh --vault "$HOME/.strata-memory"
"$HOME/.strata-memory/0_core/bin/strata" doctor --vault "$HOME/.strata-memory"
```

State that this rebuilds the release binary and derived index while preserving
user Markdown and `0_core/config/configs.yaml`. It must not instruct users to
edit shell profiles or manually copy a binary.

## Verification

- The captured failing executable produces the red `memory_index.id` error in
  an isolated vault before replacement.
- The same command exits zero after the updated binary is installed, without
  creating a duplicate target or archive.
- A duplicate-ID promotion with `--json` exits nonzero and emits the structured
  `duplicate_document_id` error.
- Run `test/rust_promote_test.sh` and `test/rust_index_backend_test.sh`.
- In an isolated vault, verify an active search finds the promoted page and
  `--include-archived` can find its archived copy.
- Update the live-vault bug note to resolved only after the regression tests
  pass; do not modify the live vault as part of this repository change.

## Out of Scope

Existing, manually created Markdown files may still share an identical logical
frontmatter ID. That is a separate data-quality problem and should receive a
dedicated duplicate-ID diagnostic if it recurs. It is not caused by the normal
current promotion flow.
