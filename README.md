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
  <img alt="Index: SQLite default" src="https://img.shields.io/badge/index-sqlite%20default-white?style=for-the-badge&labelColor=000000">
</p>

<p align="center">
  <a href="docs/project_spec.md">Spec</a>
  ·
  <a href="docs/adr/">ADRs</a>
  ·
  <a href="docs/implementation_plan.md">Implementation Plan</a>
  ·
  <a href="docs/AGENTS_template.md">AGENTS Template</a>
</p>

---

## What It Is

Strata-Memory is a local-first memory system for agentic work. Markdown files are canonical; the local search database is a rebuildable derived index.

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

Required:

```text
rust cargo sqlite3 bash
```

Strata-Memory does not auto-install dependencies. On Debian/Ubuntu-like systems:

```bash
sudo apt install cargo rustc sqlite3 bash gawk sed findutils coreutils
```

On Apple Silicon macOS with Homebrew:

```bash
brew install rust
```

Supported local-build platforms are Linux and Apple Silicon macOS (`arm64`). Intel macOS is not supported.

SQLite should support FTS5 for full search indexing. The Rust CLI detects FTS5 support and records migration `002` only when available.

## Install and First Run

Install into the default vault at `~/.strata-memory`:

```bash
./install.sh
```

The installer builds the release binary, initializes the vault structure, updates managed files, and preserves existing user configuration and content.

Add the installed CLI to your shell path for the commands below:

```bash
export PATH="$HOME/.strata-memory/0_core/bin:$PATH"
```

Create the index, validate the vault, and run a first search:

```bash
strata db-migrate --vault ~/.strata-memory
strata refresh --vault ~/.strata-memory
strata doctor --vault ~/.strata-memory
strata search --query "example" --vault ~/.strata-memory
```

Useful installer options:

```bash
./install.sh --vault /path/to/vault
./install.sh --vault ~/.strata-memory --json
STRATA_CARGO_OFFLINE=1 ./install.sh
```

## Common Commands

| Command | Purpose |
|---|---|
| `strata init --vault PATH [--json]` | Create the vault directory layout. |
| `strata db-migrate --vault PATH [--json]` | Create or update the active index backend schema. |
| `strata refresh --vault PATH [--json]` | Rebuild the active index from Markdown. |
| `strata config-compile --vault PATH [--json]` | Validate config and write `0_core/cache/config.compiled.json`. |
| `strata agents-generate --vault PATH [--json]` | Generate vault `AGENTS.md` while preserving manual sections. |
| `strata index [--target FILE \| --full] --vault PATH [--json]` | Index one file or the full vault. |
| `strata search --query TEXT --vault PATH [--limit N] [--include-archived] [--paths-only] [--hybrid] [--json]` | Search indexed memory. |
| `strata semantic-refresh --vault PATH [--json]` | Rebuild local semantic embeddings. |
| `strata semantic-status --vault PATH [--json]` | Report semantic search readiness. |
| `strata link-review --vault PATH [--json]` | Review local Markdown links. Broken durable links are blocking errors. |
| `strata normalize --target FILE --vault PATH [--check] [--json]` | Normalize constrained Markdown frontmatter. |
| `strata promote --source FILE --to 2_knowledge[/ROOM]\|3_intelligence[/ROOM] [--new-slug SLUG] --vault PATH [--json]` | Promote a draft into a durable tier or concrete room and archive the original. |
| `strata retention --vault PATH [--apply] [--json]` | Report or delete archived drafts past retention policy. |
| `strata doctor --vault PATH [--json]` | Check vault health without mutating files. |
| `strata tag-review --vault PATH [--json]` | Review frontmatter tags against allowed tags. |
| `strata room-review --vault PATH [--json]` | Report files outside registered room patterns. |
| `strata privacy-review --vault PATH [--json]` | Report local-path and privacy warnings. |

`strata promote --to 2_knowledge` and `--to 3_intelligence` preserve the draft subfolder. For example, `1_draft/research/foo.md` promotes to `2_knowledge/research/foo.md`. Passing a concrete room such as `--to 2_knowledge/entity/website` promotes directly into that room.

Full indexing reports progress on stderr when run interactively. For non-interactive runs, set `STRATA_INDEX_PROGRESS_EVERY=N`, or `0` to disable progress.

## Index Backends

SQLite is the stable default. New vaults use:

```yaml
index:
  backend: sqlite
```

Existing configs without `index.backend` also use SQLite.

Embedded local Turso is available for evaluation by setting `backend: turso` and running `strata refresh`. It uses `0_core/db/strata-turso.db`, never falls back to SQLite, and does not use Turso Cloud or synchronization. Turso remains experimental because rebuild performance and index size do not yet meet the SQLite replacement gates.

## Draft Templates

Installed vault templates live under `0_core/template`. Research drafts can start from:

```text
0_core/template/draft/research-draft.md
```

The research draft template records generation context before review: `type`, `generated_by`, `generated_at`, `research_method`, `confidence`, `summary`, and `sources_cited`. Drafts use `strata: "1_draft"` and `status: "pending"` until promotion.

## Database and Recovery

Markdown files are the source of truth. Index databases are derived and rebuildable. SQLite uses `0_core/db/strata.db`; Turso uses `0_core/db/strata-turso.db`.

If indexing reports lock, journal, or disk I/O errors after a crash or reboot, first run:

```bash
strata doctor --vault ~/.strata-memory --json
```

After confirming the filesystem and database directory are writable, rebuild the active backend:

```bash
strata refresh --vault ~/.strata-memory --json
strata doctor --vault ~/.strata-memory --json
```

Do not delete Markdown content during index recovery. Delete an index database only when normal refresh recovery fails and after preserving a copy for diagnosis.

## Reviews and Validation

Run these after bulk edits:

```bash
strata doctor --vault ~/.strata-memory --json
strata tag-review --vault ~/.strata-memory --json
strata room-review --vault ~/.strata-memory --json
strata link-review --vault ~/.strata-memory --json
strata privacy-review --vault ~/.strata-memory --json
```

Review semantics:

- tag and room issues are warnings in `doctor`
- broken durable local links are blocking errors
- privacy review reports warnings without blocking

## Development

Run focused checks:

```bash
bash -n install.sh src/script/migration.sh src/script/lib/*.sh test/*.sh
cargo check --manifest-path src/rust/strata/Cargo.toml
bash test/rust_doctor_test.sh
```

Run the full test suite:

```bash
for f in test/*_test.sh; do
  bash "$f"
done
```

Run the Linux core suite in Docker:

```bash
test/linux_container_smoke.sh linux/arm64
test/linux_container_smoke.sh linux/amd64
```

Tests use fixture vaults under `test/tmp/`; they do not operate on the installed private vault.

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

## Future Evaluation

The current Turso verdict is `continue-evaluation`: it is functionally usable but does not yet meet SQLite replacement gates for rebuild performance and index size. SQLite remains the default, and Turso remains experimental and opt-in.

Re-evaluate Turso after its first upstream stable release intended for production use. See the [latest Turso evaluation](docs/evaluations/turso-latest.md) for results, failed gates, and the next evaluation criteria.

## License

MIT. See [License.md](License.md).
