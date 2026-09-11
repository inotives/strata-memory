# Installation Bootstrap Implementation Phase

**Status:** Approved for implementation  
**Updated:** 2026-09-11

## Goal

Make one installer command leave a Strata vault ready for use. `./install.sh`
must build and install Strata, migrate the active index backend, rebuild the
derived index, and verify vault health.

The default vault remains `~/.strata-memory`. A user selects another knowledge
vault with the existing `--vault PATH` option:

```bash
./install.sh --vault /path/to/wiki
```

## Public Contract

- Keep the command interface as `install.sh [--vault PATH] [--json]`.
- Keep local release builds. Rust and Cargo remain installation prerequisites;
  this phase does not download or publish prebuilt binaries.
- Validate required runtime tools before installing and show actionable,
  platform-appropriate remediation for any missing prerequisite.
- Do not invoke Homebrew, apt, or another package manager automatically.
- Do not edit shell startup files. Human-readable completion output may show
  the optional `PATH` addition needed to invoke `strata` without its absolute
  path.

## Installer Flow

1. Resolve the vault from `--vault`, `STRATA_VAULT`, or the default path.
2. Validate Cargo/Rust and the current runtime-tool prerequisites.
3. Build the release binary, install managed files, and preserve user-owned
   configuration and vault content exactly as today.
4. Invoke the installed binary by absolute path to run, in order:
   - `db-migrate --vault <vault>`
   - `refresh --vault <vault>`
   - `doctor --vault <vault>`
5. Report success only after all three bootstrap stages succeed.

Run the bootstrap sequence on every installation, including reinstalls. This
keeps a vault compatible with a newly installed CLI and its active index
backend. If a stage fails, exit nonzero, name the failed stage, and leave the
already-installed managed files in place so the user can diagnose and rerun
the installer.

For `--json`, successful bootstrap subcommand output must not pollute stdout.
The installer continues to emit exactly one final JSON object. Failures retain
their diagnostic stderr.

## Preservation Rules

- Never overwrite `0_core/config/configs.yaml`, vault Markdown, `.gitignore`,
  or `AGENTS.md` when they already exist.
- Index rebuilds remain safe because the index database is derived from the
  canonical Markdown vault.
- A custom `--vault PATH` receives the identical layout, managed files, and
  bootstrap behavior as the default vault.

## Verification

Extend `test/install_test.sh` to cover:

1. Fresh custom-vault installation creates a migrated, searchable vault that
   passes `doctor`.
2. Reinstallation preserves a valid user configuration and Markdown content,
   then leaves the rebuilt index healthy.
3. Each bootstrap-stage failure returns nonzero and identifies the stage.
4. Missing Cargo or a required runtime tool reports remediation and never
   attempts package installation.
5. `--json` stdout is exactly one parseable final result.

## Documentation Follow-up

Update the README during implementation to replace the manual first-run
`db-migrate`, `refresh`, and `doctor` sequence with `./install.sh`; retain the
`--vault /path/to/wiki` example and document the local-build prerequisites.
Add **vault bootstrap** to `CONTEXT.md`: the installation-time preparation of
a vault's rebuildable search infrastructure.

## Exit Criteria

- A successful installer invocation leaves either the default vault or a
  selected custom vault immediately ready for `strata search`.
- Repeat installation is safe for existing user content and configuration.
- No prebuilt-binary distribution, package-manager automation, or shell-profile
  mutation is introduced.
