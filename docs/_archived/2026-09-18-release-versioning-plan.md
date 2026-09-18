# Release Versioning Execution Plan

## Goal

Make every Strata engine release identifiable after installation, including
small fixes, without introducing a second version source or a release service.

## Current State

- `src/rust/strata/Cargo.toml` declares the package version (`0.1.0`).
- `install.sh` builds and copies the release binary into `0_core/bin/strata`.
- The CLI has no version command, so an installed vault cannot report which
  engine release it has received.
- The repository has no documented version-bump, tag, or release-note process.

## Decisions

1. Use Semantic Versioning and keep `Cargo.toml` as the sole source of the
   Strata release version.
   - This change is the first `0.1.1` release over the existing `0.1.0`
     baseline.
   - Patch (`0.1.2`) for compatible bug fixes and documentation-only release
     corrections after this release.
   - Minor (`0.2.0`) for backward-compatible CLI or vault capabilities.
   - Major (`1.0.0`) only for intentionally breaking user-facing behavior.
2. Add `strata version [--json]`. The binary reads the compile-time Cargo
   package version; it does not read a mutable file from the vault.
3. Make the installer report the installed version in both normal and JSON
   completion output. This lets an automated install verify the binary it
   received without parsing `--version` output separately.
4. Use annotated Git tags named `vX.Y.Z` and a root `CHANGELOG.md` for
   release history. Creating a GitHub Release remains a manual release step;
   no CI or download pipeline is required for this small change.

## Scope

### CLI

- Add a `Version` command to the existing CLI parser and usage text.
- Print `strata X.Y.Z` in human output.
- Print exactly `{"ok":true,"name":"strata","version":"X.Y.Z"}` with
  `--json`.
- Keep `strata version` independent of a vault path, configuration, database,
  and filesystem state.

### Installer

- Obtain the installed version from the copied `0_core/bin/strata` binary.
- Include `Installed version: X.Y.Z` in the successful human summary and add
  `version` to the existing successful JSON object without removing `ok`,
  `vault`, or `manifest`.
- Do not add a version file, network check, package-manager action, or update
  command.

### Release Practice

- Add `CHANGELOG.md` with an `Unreleased` section and the initial `0.1.0`
  baseline.
- Document the release sequence: choose the SemVer bump, move notes from
  `Unreleased`, update `Cargo.toml`, run validation, commit, create annotated
  `vX.Y.Z` tag, push branch and tag, and optionally publish a GitHub Release.
- Update installation/update documentation to show verification with
  `strata version` after `./install.sh`.

## Verification

1. Add a focused CLI test proving `strata version` reports the Cargo package
   version in human and JSON modes without a vault.
2. Extend the installer test to assert normal and JSON output include the
   installed version.
3. Run `cargo fmt --check`, `cargo check`, the focused version test,
   `bash test/install_test.sh`, and `git diff --check`.
4. In a temporary vault, run `install.sh`, then compare `strata version` with
   the installer-reported version. Do not modify the live vault for this test.

## Non-Goals

- Automatically selecting or incrementing versions.
- Building downloadable release artifacts or bypassing Rust prerequisites.
- Auto-updating installed vaults from the network.
- Changing Markdown document `version` frontmatter or database migration
  versions.
