# Add a Non-Indexed `0_resource/` Vault Area

Status: Proposed

## Goal

Add a vault-root `0_resource/` area for assets embedded or linked by Markdown,
without treating those files as Strata documents.

## Decisions

1. `0_resource/` is not a Strata tier and is never indexed, searched,
   normalized, promoted, or included in doctor and review scans.
2. Fresh vaults create these directories:
   - `0_resource/images/`
   - `0_resource/scripts/`
   - `0_resource/data/`
   - `0_resource/other/`
3. Markdown documents reference resources using relative POSIX paths. Absolute
   paths and `file://` links remain prohibited.
4. Resources do not require Strata frontmatter. Scripts stored in
   `0_resource/scripts/` are not automatically executable and remain subject
   to existing execution-allowlist rules.
5. This phase adds no asset CLI, resource metadata schema, asset-copy command,
   or automatic execution behavior.

## Implementation Plan

1. Add the resource directories to the Rust vault initialization layout and
   ensure installer-created vaults receive the same layout.
2. Keep indexing and review collection limited to their existing roots; add an
   explicit exclusion/contract test so future collection changes cannot make
   `0_resource/` discoverable.
3. Update README and both managed/repository AGENTS templates to explain:
   - the purpose and subfolder convention of `0_resource/`;
   - relative-link usage for embedded assets;
   - non-indexing, non-frontmatter, and non-promotion rules;
   - the no-auto-execution rule for stored scripts.
4. Update install and index/review tests to verify a fresh vault creates the
   layout and resource files do not surface in refresh, search, doctor,
   link-review, tag-review, or room-review output.

## Verification

1. A fresh installer-created vault contains all four resource subfolders.
2. A Markdown fixture and a binary-like fixture under `0_resource/` are absent
   from SQLite and Turso refresh/search results.
3. Resource Markdown causes no doctor or review findings.
4. A durable document can use a relative link to an image under
   `0_resource/images/` without producing a broken-link or room-review error.
