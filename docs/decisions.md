# Strata-Memory Decision Log

**Status:** Draft decisions from planning grill  
**Updated:** 2026-06-06

This log captures the agreed product and architecture decisions that shape the Strata-Memory specification. The public project repo remains implementation source; the private user vault lives at `~/.strata-memory`.

## Core Direction

- Strata-Memory is a successor format to the existing Agent Memory layout, not a direct continuation of the old folder names.
- The old `~/.agent-knowledge/memory` remains intact and read-only during migration.
- Migration writes into `~/.strata-memory` section by section.
- Old drafts are not migrated. New Strata drafts start from empty subfolders.
- The architecture is **core plus three tiers**, not four tiers: `0_core` is not a promotion tier.

## Canonical Layout

- Canonical private vault path: `~/.strata-memory`.
- Canonical installed vault layout:

```text
~/.strata-memory/
├── 0_core/
├── 1_draft/
├── 2_knowledge/
└── 3_intelligence/
```

- Canonical migration naming map:

```text
0_configs        -> 0_core
1_drafts         -> 1_draft
2_knowledges     -> 2_knowledge
3_intelligences  -> 3_intelligence
skills           -> skill
agents           -> agent
reports          -> report
```

- Archive folders use `_archived` everywhere.
- Paths are lowercase and hyphen-normalized. Entity display casing is preserved in metadata, not paths.
- Entity folders use lowercase paths such as `entity/stock/aapl/`, with display fields such as `ticker: AAPL`.

## Public Repo vs Private Vault

- The public repo contains the Strata engine, docs, tests, examples, installer, and specification.
- The private repo contains only the user vault at `~/.strata-memory`.
- The private-vault `AGENTS.md` starter lives in the public repo at `docs/AGENTS_template.md`; root `AGENTS.md` is generated inside the installed private vault.
- The public repo should use a normal project layout:

```text
src/
example/
test/
install.sh
docs/project_spec.md
docs/
```

- The installer copies/syncs managed engine files into `~/.strata-memory/0_core/`.
- Installed engine files are tracked with a manifest.
- User customization happens through override files, not by editing managed templates directly.

## Source of Truth

- Markdown files are canonical.
- SQLite is a rebuildable derived index and cache.
- Commands mutate Markdown/filesystem state first, then re-index affected paths.
- If indexing fails after a file operation, recovery is to re-run `strata index`.

## Frontmatter and Metadata

- Files use a constrained YAML subset for human-authored Markdown.
- SQLite stores normalized JSON for arrays and metadata.
- Quote full timestamps with colons:

```yaml
created: "2026-06-06"
modified: "2026-06-06"
promoted_at: "2026-06-06T15:32:04Z"
```

- Parsers split key/value pairs on the first colon only.
- Draft descriptions may be empty.
- `2_knowledge`, `skill`, `agent`, and `workflow` descriptions are required.
- `sources` remains part of durable provenance.
- Empty `sources: []` is allowed only with `source_note`.
- Reports do not require frontmatter.
- Generated reports use `status: generated`.

## Drafts, Promotion, and Retention

- Promotion archives the original draft under `1_draft/_archived/` and creates a curated artifact in `2_knowledge` or `3_intelligence`.
- Archived drafts are indexed but excluded from default search.
- Archived drafts are retained for a configurable period, default 180 days.
- Retention is report-only by default. Deletion requires `--apply`.
- Deletion logs are kept indefinitely under `3_intelligence/report/maintenance/`.

## Rooms and Profiles

- `AGENTS.md` is generated from templates and profile config, with protected manual sections.
- Profiles such as `coder`, `trader`, and `researcher` define default room structures.
- Users can create folders manually, but unregistered rooms are flagged.
- Room registration supports path patterns plus metadata.
- Recursive room roots prevent nested folders like `entity/stock/aapl/daily/` from being flagged.
- Recommended depth policy:
  - `entity/*/*`: recursive
  - `skill/<domain>/<slug>` bundles: recursive
  - `agent/<domain>`: shallow by default
  - `research`, `note`, `preference`, `concept`: shallow unless profile overrides

## Tags and Slugs

- Tags use a controlled vocabulary in config.
- Unknown tags warn in drafts and are reviewed at promotion.
- `strata tag-review` detects similar/new tags and can update the allowed tag list with human approval.
- Durable artifact slugs are lowercase, hyphenated, and conservative.
- Entity identifiers may preserve domain conventions in metadata, not in paths.

## Search and Indexing

- MVP uses SQLite FTS5 only. Semantic/vector search is deferred.
- Store full Markdown content in SQLite as disposable cache.
- Include `content_hash`.
- Use weighted ranking: title > description > tags > content.
- Default search returns metadata plus snippets, not full content.
- Every CLI supports `--json`.
- Index a simple link graph in MVP.
- Block broken local links in durable tiers; warn in drafts.
- Extract Markdown sections in MVP for better snippets and future retrieval.
- Warn on oversized pages using room-specific line thresholds.

## Runtime and Dependencies

- Use Bash 3.2-compatible scripts.
- MVP target is Linux acceptance, with macOS as a design constraint.
- Watchers are post-migration, not MVP.
- Required bootstrap tools: bash, sqlite3, awk, sed, find, sort, mktemp.
- Full mode requires `yq` and `jq`.
- `strata init` does not auto-install dependencies; it prints install guidance.
- Use vault-local temp files under `0_core/tmp/`.
- Use `mktemp` with explicit templates under `0_core/tmp/`.

## Safety and Trust

- Skill scripts require an execution allowlist.
- Imported external skills and agents are staged through `1_draft` before promotion.
- Add `strata privacy-review` for warning-only private-data checks in MVP.
- Tests never touch real vaults; they use isolated fixture vaults under test temp directories.
- The system supports git but does not require it.

## Roadmap Gates

- Phase 0: public engine repo spec and installer.
- Phase 1: empty Strata vault MVP.
- Phase 2: section migration from `~/.agent-knowledge/memory`.
- Phase 3: migration validation and cleanup.
- Phase 4: watchers and real-time sync.
- Phase 5: semantic/vector search.
- Phase 6: workflow runner and richer automation.

Watchers must not start until migration validation is complete.
