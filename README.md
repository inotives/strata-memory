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
  <img alt="Runtime: Bash 3.2" src="https://img.shields.io/badge/runtime-bash%203.2-white?style=for-the-badge&labelColor=000000">
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

This repository is the public engine repo. It contains the installer, scripts, templates, tests, and documentation for installing Strata into a private vault.

By default, the private vault lives at:

```text
~/.strata-memory
```

## Core Model

Strata uses a core-plus-three-tier lifecycle:

```text
0_core/          # installed engine kernel, scripts, templates, config, cache, db
1_draft/         # raw, unreviewed material
2_knowledge/     # curated durable knowledge
3_intelligence/  # skills, agents, workflows, reports
```

The public repo should not contain vault-runtime folders at its root. Engine source lives under `src/`, and `install.sh` syncs managed files into `~/.strata-memory/0_core/`.

## Dependencies

Bootstrap commands require:

```text
bash sqlite3 awk sed find sort mktemp cksum date
```

Full-mode configuration compilation requires:

```text
jq yq
```

Strata-Memory does not auto-install dependencies. On Debian/Ubuntu-like systems:

```bash
sudo apt install bash sqlite3 gawk sed findutils coreutils jq yq
```

SQLite should support FTS5 for full search indexing. The database scripts detect FTS5 support and record migration `002` only when available.

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
- copies managed engine files into `0_core/script`, `0_core/db`, `0_core/doc`, and `0_core/template`
- copies a built Rust CLI into `0_core/bin/strata` when `src/rust/strata/target/release/strata` exists
- preserves existing `0_core/config/configs.yaml`
- creates `.gitignore` and `AGENTS.md` only when missing
- writes `0_core/manifest.json`

After install, run:

```bash
~/.strata-memory/0_core/script/db-migrate.sh --vault ~/.strata-memory
~/.strata-memory/0_core/script/doctor.sh --vault ~/.strata-memory
```

## Optional Rust Indexer

Phase 4a adds an optional Rust CLI behind the existing Bash command contract. It is not required for install. Build it before running `install.sh` when you want the installed `index.sh` wrapper to delegate indexing to Rust:

```bash
cargo build --manifest-path src/rust/strata/Cargo.toml --release
./install.sh --vault ~/.strata-memory
```

Installed shape:

```text
~/.strata-memory/0_core/bin/strata
~/.strata-memory/0_core/script/index.sh
```

`index.sh` keeps the public command stable and delegates to `0_core/bin/strata` only when that binary exists. Set `STRATA_INDEX_BASH_FALLBACK=1` to force the Bash indexer.

## Common Commands

Run all commands from the installed vault scripts. Most commands accept `--vault PATH`; most review commands also accept `--json`.

| Command | Purpose |
|---|---|
| `init.sh --vault PATH` | Create the vault directory layout. |
| `db-migrate.sh --vault PATH [--json]` | Create or update the derived SQLite schema. |
| `index.sh [--target FILE | --full] --vault PATH [--json]` | Index Markdown files into SQLite. |
| `search.sh --query TEXT --vault PATH [--limit N] [--include-archived] [--paths-only] [--json]` | Search indexed memory with SQLite FTS5. |
| `normalize.sh --target FILE [--vault PATH] [--check] [--json]` | Normalize constrained Markdown frontmatter. |
| `promote.sh --source FILE --to ROOM [--slug NAME] [--vault PATH] [--json]` | Promote a draft into a durable tier and archive the original. |
| `doctor.sh --vault PATH [--json]` | Check vault health without mutating files. |
| `tag-review.sh --vault PATH [--json]` | Review frontmatter tags against allowed tags. |
| `room-review.sh --vault PATH [--json]` | Report files outside registered room patterns. |
| `link-review.sh --vault PATH [--json]` | Review local Markdown links. Broken durable links are blocking errors. |
| `privacy-review.sh --vault PATH [--json]` | Report local-path and privacy warnings. |
| `config-compile.sh --vault PATH [--json]` | Validate config and write `0_core/cache/config.compiled.json`. Requires `jq` and `yq`. |
| `agents-generate.sh --vault PATH [--json]` | Generate vault `AGENTS.md` while preserving manual sections. |
| `retention.sh --vault PATH [--apply] [--json]` | Report or delete archived drafts past retention policy. |

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
~/.strata-memory/0_core/script/doctor.sh --vault ~/.strata-memory --json
```

The `findmnt` output should not show `ro`. `doctor.sh` reports whether `0_core/tmp` and `0_core/db` are writable.

After the filesystem is healthy, rebuild only the derived index:

```bash
rm -f ~/.strata-memory/0_core/db/strata.db ~/.strata-memory/0_core/db/strata.db-journal
~/.strata-memory/0_core/script/db-migrate.sh --vault ~/.strata-memory
~/.strata-memory/0_core/script/index.sh --vault ~/.strata-memory --full --json
```

Validate the rebuilt database:

```bash
sqlite3 ~/.strata-memory/0_core/db/strata.db 'PRAGMA quick_check;'
~/.strata-memory/0_core/script/doctor.sh --vault ~/.strata-memory --json
```

## Reviews And Validation

Run these after bulk edits:

```bash
~/.strata-memory/0_core/script/doctor.sh --vault ~/.strata-memory --json
~/.strata-memory/0_core/script/tag-review.sh --vault ~/.strata-memory --json
~/.strata-memory/0_core/script/room-review.sh --vault ~/.strata-memory --json
~/.strata-memory/0_core/script/link-review.sh --vault ~/.strata-memory --json
~/.strata-memory/0_core/script/privacy-review.sh --vault ~/.strata-memory --json
```

Review semantics:

- tag and room issues are warnings in `doctor`
- broken durable local links are blocking errors
- privacy review reports warnings without blocking
- missing full-mode dependencies (`jq`, `yq`) are warnings unless running full-mode config compilation

## Development

Run focused checks:

```bash
rtk bash -n install.sh src/script/*.sh src/script/lib/*.sh test/*.sh
rtk bash test/doctor_test.sh
```

Run the full shell test suite:

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
