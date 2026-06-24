<p align="center">
  <img src="logo.png" alt="Strata-Memory logo" width="220">
</p>

<h1 align="center">strata-memory</h1>

<p align="center">
  Local-first agentic memory: drafts become knowledge, knowledge becomes executable intelligence.
</p>

<p align="center">
  <a href="License.md"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-white?style=for-the-badge&labelColor=000000"></a>
  <a href="docs/project_spec.md"><img alt="Status: implementation" src="https://img.shields.io/badge/status-implementation-white?style=for-the-badge&labelColor=000000"></a>
  <img alt="Runtime: Rust CLI" src="https://img.shields.io/badge/runtime-rust%20cli-white?style=for-the-badge&labelColor=000000">
  <img alt="Shell: migration helper" src="https://img.shields.io/badge/shell-migration%20helper-white?style=for-the-badge&labelColor=000000">
  <img alt="Index: SQLite FTS5" src="https://img.shields.io/badge/index-sqlite%20fts5-white?style=for-the-badge&labelColor=000000">
</p>

<p align="center">
  <a href="docs/project_spec.md">Spec</a>
  ·
  <a href="docs/decisions.md">Decisions</a>
  ·
  <a href="docs/implementation_plan.md">Implementation Plan</a>
  ·
  <a href="docs/AGENTS_template.md">AGENTS Template</a>
</p>

---

## What It Is

Strata-Memory is a local-first memory system for agentic work. Markdown files are canonical. SQLite is a rebuildable derived index for search, metadata queries, link review, and retrieval workflows.

This repository is the public engine repo. It contains the Rust CLI, installer, migration helper, templates, tests, and documentation for installing Strata into a private vault.

By default, the private vault lives at:

```text
~/.strata-memory
```

## Core Model

Strata uses a core-plus-three-tier lifecycle:

```text
0_core/          # installed engine kernel, Rust binary, wrappers, templates, config, cache, db
1_draft/         # raw, unreviewed material
2_knowledge/     # curated durable knowledge
3_intelligence/  # skills, agents, workflows, reports
```

The public repo should not contain vault-runtime folders at its root. Engine source lives under `src/`, and `install.sh` syncs managed files into `~/.strata-memory/0_core/`.

## Dependencies

Primary runtime:

```text
rust cargo sqlite3
```

Shell wrappers and remaining Bash fallback commands require:

```text
bash awk sed find sort mktemp cksum date
```

Full-mode configuration compilation requires:

```text
jq yq
```

Strata-Memory does not auto-install dependencies. On Debian/Ubuntu-like systems:

```bash
sudo apt install cargo rustc sqlite3 bash gawk sed findutils coreutils jq yq
```

Supported local-build platforms are Linux and Apple Silicon macOS (`arm64`). Intel macOS is not supported.

SQLite should support FTS5 for full search indexing. The Rust CLI detects FTS5 support and records migration `002` only when available.

## Install

Install into the default vault:

```bash
./install.sh
```

Install into a custom vault:

```bash
./install.sh --vault /path/to/vault
```

Machine-readable install output:

```bash
./install.sh --vault ~/.strata-memory --json
```

The installer:

- initializes the vault structure
- validates Linux or Apple Silicon macOS and runs `cargo build --release`
- passes Cargo `--offline` when `STRATA_CARGO_OFFLINE=1`
- copies managed engine files into `0_core/bin`, `0_core/db`, `0_core/doc`, `0_core/template`, and the one-off migration helper under `0_core/script`
- copies the built Rust CLI into `0_core/bin/strata`
- preserves existing `0_core/config/configs.yaml`
- creates `.gitignore` and `AGENTS.md` only when missing
- writes `0_core/manifest.json`

After install, run:

```bash
~/.strata-memory/0_core/bin/strata db-migrate --vault ~/.strata-memory
~/.strata-memory/0_core/bin/strata doctor --vault ~/.strata-memory
```

## Rust CLI

The primary engine is the installed Rust binary:

```text
~/.strata-memory/0_core/bin/strata
```

Runtime commands:

```text
strata init --vault PATH [--json]
strata db-migrate --vault PATH [--json]
strata config-compile --vault PATH [--json]
strata agents-generate --vault PATH [--json]
strata index [--target FILE | --full] --vault PATH [--json]
strata search --query TEXT --vault PATH [--limit N] [--include-archived] [--paths-only] [--json]
strata link-review --vault PATH [--json]
strata normalize --target FILE --vault PATH [--check] [--json]
strata promote --source FILE --to 2_knowledge[/ROOM]|3_intelligence[/ROOM] [--new-slug SLUG] --vault PATH [--json]
strata retention --vault PATH [--apply] [--json]
strata doctor --vault PATH [--json]
strata tag-review --vault PATH [--json]
strata room-review --vault PATH [--json]
strata privacy-review --vault PATH [--json]
```

`0_core/script/migration.sh` remains as one-off legacy migration tooling. It is not part of the normal runtime command surface.

Rust full indexing reports progress on stderr when run interactively. For non-interactive runs, set `STRATA_INDEX_PROGRESS_EVERY=N` to print progress every N scanned files, or `0` to disable progress.

## Common Commands

Use the installed Rust CLI for runtime commands.

| Command | Purpose |
|---|---|
| `strata init --vault PATH [--json]` | Create the vault directory layout. |
| `strata db-migrate --vault PATH [--json]` | Create or update the derived SQLite schema. |
| `strata config-compile --vault PATH [--json]` | Validate config and write `0_core/cache/config.compiled.json`. |
| `strata agents-generate --vault PATH [--json]` | Generate vault `AGENTS.md` while preserving manual sections. |
| `strata index [--target FILE \| --full] --vault PATH [--json]` | Index Markdown files into SQLite. |
| `strata search --query TEXT --vault PATH [--limit N] [--include-archived] [--paths-only] [--json]` | Search indexed memory with SQLite FTS5. |
| `strata link-review --vault PATH [--json]` | Review local Markdown links. Broken durable links are blocking errors. |
| `strata normalize --target FILE --vault PATH [--check] [--json]` | Normalize constrained Markdown frontmatter. |
| `strata promote --source FILE --to 2_knowledge[/ROOM]\|3_intelligence[/ROOM] [--new-slug SLUG] --vault PATH [--json]` | Promote a draft into a durable tier or concrete room and archive the original. |
| `strata retention --vault PATH [--apply] [--json]` | Report or delete archived drafts past retention policy. |
| `strata doctor --vault PATH [--json]` | Check vault health without mutating files. |
| `strata tag-review --vault PATH [--json]` | Review frontmatter tags against allowed tags. |
| `strata room-review --vault PATH [--json]` | Report files outside registered room patterns. |
| `strata privacy-review --vault PATH [--json]` | Report local-path and privacy warnings. |
| `0_core/script/migration.sh --from PATH --to PATH --section NAME\|--all [--json]` | One-off legacy Agent Memory migration helper. |

`strata promote --to 2_knowledge` and `--to 3_intelligence` preserve the draft subfolder. For example, `1_draft/research/foo.md` promotes to `2_knowledge/research/foo.md`. Passing a concrete room such as `--to 2_knowledge/entity/website` promotes directly into that room.

## Draft Templates

Installed vault templates live under `0_core/template`. Research drafts can start from:

```text
0_core/template/draft/research-draft.md
```

The research draft template records generation context before review: `type`, `generated_by`, `generated_at`, `research_method`, `confidence`, `summary`, and `sources_cited`. Drafts use `strata: "1_draft"` and `status: "pending"` until promotion.

## Database And Recovery

Markdown files are the source of truth. The SQLite database at `~/.strata-memory/0_core/db/strata.db` is a derived index and can be rebuilt.

If indexing reports SQLite lock, journal, or disk I/O errors after a crash or reboot, first check that the vault filesystem is writable:

```bash
findmnt -T ~/.strata-memory -no TARGET,OPTIONS
~/.strata-memory/0_core/bin/strata doctor --vault ~/.strata-memory --json
```

The `findmnt` output should not show `ro`. `strata doctor` reports whether `0_core/tmp` and `0_core/db` are writable.

After the filesystem is healthy, rebuild only the derived index:

```bash
rm -f ~/.strata-memory/0_core/db/strata.db ~/.strata-memory/0_core/db/strata.db-journal
~/.strata-memory/0_core/bin/strata db-migrate --vault ~/.strata-memory
~/.strata-memory/0_core/bin/strata index --vault ~/.strata-memory --full --json
```

Validate the rebuilt database:

```bash
sqlite3 ~/.strata-memory/0_core/db/strata.db 'PRAGMA quick_check;'
~/.strata-memory/0_core/bin/strata doctor --vault ~/.strata-memory --json
```

## Reviews And Validation

Run these after bulk edits:

```bash
~/.strata-memory/0_core/bin/strata doctor --vault ~/.strata-memory --json
~/.strata-memory/0_core/bin/strata tag-review --vault ~/.strata-memory --json
~/.strata-memory/0_core/bin/strata room-review --vault ~/.strata-memory --json
~/.strata-memory/0_core/bin/strata link-review --vault ~/.strata-memory --json
~/.strata-memory/0_core/bin/strata privacy-review --vault ~/.strata-memory --json
```

Review semantics:

- tag and room issues are warnings in `doctor`
- broken durable local links are blocking errors
- privacy review reports warnings without blocking
- missing full-mode dependencies (`jq`, `yq`) are warnings in `doctor`

## Development

Run focused checks:

```bash
rtk bash -n install.sh src/script/migration.sh src/script/lib/*.sh test/*.sh
rtk cargo check --manifest-path src/rust/strata/Cargo.toml
rtk bash test/rust_doctor_test.sh
```

Run the full test suite:

```bash
for f in test/*_test.sh; do
  rtk bash "$f"
done
```

The test suite uses fixture vaults under `test/tmp/`.

## Repository Layout

```text
strata-memory/
├── src/
│   ├── script/
│   ├── template/
│   ├── db/
│   └── doc/
├── test/
├── docs/
├── install.sh
├── logo.png
├── License.md
└── README.md
```

## License

MIT. See [License.md](License.md).
