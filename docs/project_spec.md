# Strata-Memory Project Specification

**Version:** 0.2  
**Status:** Draft  
**Updated:** 2026-06-06

Strata-Memory is a local-first agentic memory system. It organizes human and agent knowledge through a disciplined lifecycle: raw drafts, curated knowledge, and executable intelligence. The system uses Markdown files as the source of truth and SQLite as a rebuildable index for search, metadata queries, link review, and future retrieval features.

This specification describes the successor format for the existing Agent Memory layout. Migration from `~/.agent-knowledge/memory` to `~/.strata-memory` is explicit, section-based, and read-only against the old memory.

## 1. Goals

- Keep personal memory inspectable, editable, and portable as local files.
- Separate unverified drafts from durable knowledge and executable intelligence.
- Make promotion human-in-the-loop and auditable.
- Keep agent prompts and command references generated from the vault contract.
- Support private vault storage in git while keeping the public engine repo clean.
- Start with reliable lifecycle and search behavior before adding watchers or vectors.

## 2. Non-Goals for MVP

- No file watcher daemon in MVP.
- No semantic/vector search in MVP.
- No automatic dependency installation.
- No workflow runner beyond documented commands.
- No migration of legacy drafts from `~/.agent-knowledge/memory`.
- No macOS acceptance testing in MVP, though scripts should avoid unnecessary Linux-only assumptions.

## 3. Repository and Vault Model

Strata has two separate locations:

```text
~/workspaces/strata-memory/   # public engine repo
~/.strata-memory/             # private user vault repo
```

The public repo contains implementation source, examples, docs, tests, and install tooling. The private vault contains personal memory and an installed copy of managed engine files.

### 3.1 Public Engine Repo Layout

```text
strata-memory/
├── src/
│   ├── script/
│   ├── template/
│   ├── db/
│   └── doc/
├── example/
├── test/
├── docs/
│   ├── AGENTS_template.md
│   ├── decisions.md
│   └── implementation_plan.md
├── install.sh
└── README.md
```

The public repo does not contain a real vault-runtime `AGENTS.md`. `docs/AGENTS_template.md` is the starter/template for the private vault prompt. The installed private vault gets a generated root `AGENTS.md`.

### 3.2 Installed Private Vault Layout

```text
~/.strata-memory/
├── 0_core/
│   ├── config/
│   │   └── configs.yaml
│   ├── cache/
│   ├── db/
│   │   ├── strata.db
│   │   ├── schema.sql
│   │   └── migrations/
│   ├── doc/
│   ├── script/
│   │   └── lib/
│   ├── template/
│   ├── template_override/
│   ├── test/
│   ├── tmp/
│   └── manifest.json
├── 1_draft/
├── 2_knowledge/
├── 3_intelligence/
└── AGENTS.md
```

`0_core` is not a tier. It contains the installed kernel: config, scripts, schema, generated docs, templates, cache, test helpers, and temp files.

## 4. Three-Tier Memory Lifecycle

```text
1_draft  ->  2_knowledge  ->  3_intelligence
raw          curated          executable
```

### 4.1 `1_draft`

Unverified ingestion and working material. Drafts may be incomplete and may have empty descriptions.

Default subfolders:

```text
1_draft/
├── research/
├── note/
├── skill/
├── agent/
├── workflow/
├── session/
└── _archived/
```

Archived drafts are provenance. They are indexed but excluded from default search.

### 4.2 `2_knowledge`

Curated, reviewed, durable knowledge. Content here must be human-approved or explicitly imported as curated.

Common rooms:

```text
2_knowledge/
├── concept/
├── entity/
├── research/
├── note/
├── preference/
└── _archived/
```

Profiles can define room patterns such as:

```text
entity/stock/*
entity/cryptocurrency/*
entity/project/*
entity/tool/*
```

Entity paths are lowercase. Display identifiers live in metadata, for example `ticker: AAPL`.

### 4.3 `3_intelligence`

Executable or operational intelligence: skills, agents, workflows, and generated reports.

```text
3_intelligence/
├── skill/
├── agent/
├── workflow/
├── report/
└── _archived/
```

- `skill/`: reusable capability bundles with `SKILL.md`, optional `script/`, `resource/`, and `test/`.
- `agent/`: persona definitions written in second person.
- `workflow/`: orchestration instructions across skills, agents, commands, and reports.
- `report/`: generated outputs. Reports are searchable but not durable authority by default.

## 5. Frontmatter Contract

Markdown files use constrained YAML frontmatter. SQLite stores normalized JSON for arrays and metadata.

### 5.1 Constrained YAML Rules

- Flat scalar fields.
- Arrays as block lists.
- Quote timestamps containing colons.
- Split key/value parsing on the first colon only.
- No YAML anchors, aliases, or advanced YAML features.
- Nested data belongs in `metadata` only when required.

### 5.2 Full Schema for Drafts and Knowledge

```yaml
---
id: "mem_20260606_153012_a1b2c3"
title: "Document Title"
description: "Short semantic summary for search."
strata: "2_knowledge"
status: "verified"
tags:
  - memory
  - sqlite
sources:
  - "../../1_draft/_archived/research/example.md"
source_note: "Promoted from archived draft."
version: 1
last_edit_summary: "Clarified lifecycle policy."
created: "2026-06-06"
modified: "2026-06-06"
promoted_at: "2026-06-06T15:32:04Z"
---
```

Validation:

- `1_draft`: `description` may be empty; status is `pending` or `archived`.
- `2_knowledge`: `description` required; status is `verified` or `archived`; `sources` required and may be empty only with `source_note`.
- `version` increments only for semantic content edits, not mechanical migration, normalization, archival, or promotion.
- IDs are stable across moves and migration. Generate IDs only when missing.

### 5.3 Draft Research Template

Research drafts should preserve generation context and review confidence without requiring immediate curation. The installed template lives at `0_core/template/draft/research-draft.md`.

```yaml
---
id: ""
title: "Research Title"
description: ""
strata: "1_draft"
type: "research"
status: "pending"
generated_by: "agent-or-model-name"
generated_at: "2026-06-06T13:00:00Z"
research_method: "web-search"
confidence: "medium"
tags:
  - research
sources:
  - "https://example.com/source"
sources_cited: 1
summary: "One-paragraph summary of the research question, scope, and main finding."
version: 1
created: "2026-06-06"
modified: "2026-06-06"
---
```

Draft-specific fields:

- `type`: draft kind such as `research`, `note`, `skill`, `agent`, `workflow`, or `session`.
- `generated_by`: agent, model, or toolchain that produced the draft.
- `generated_at`: UTC timestamp for generated drafts.
- `research_method`: short method label such as `web-search`, `repo-analysis`, `interview`, `manual-notes`, or `mixed`.
- `confidence`: `low`, `medium`, or `high`; this is a reviewer signal, not verification.
- `summary`: compact abstract used by agents before reading the full draft.
- `sources_cited`: count of cited external sources when that is cheaper to inspect than the full source list.

Promotion into `2_knowledge` must convert `status` to `verified`, keep the archived draft as provenance, and replace draft-only generation fields only when they no longer describe the durable artifact.

### 5.4 Intelligence Schema

Skills, agents, and workflows use the base durable schema fields:

```yaml
---
title: "Stock Pre-Open Prediction"
description: "Runs pre-open prediction across tracked tickers."
tags:
  - trading
  - workflow
sources:
  - "../../../2_knowledge/concept/pre-open-prediction.md"
source_note: "Compiled from reviewed trading workflow notes."
---
```

Workflows may add:

```yaml
inputs:
  - date
outputs:
  - prediction_cards
  - html_report
required_skills:
  - "../skill/trading/stock-pre-open-prediction/SKILL.md"
required_agents:
  - "../agent/trading/stock-analyst.md"
```

Reports require no frontmatter. The indexer assigns `strata = 3_intelligence` and `status = generated`.

## 6. Links and Sources

Local vault links must be POSIX relative Markdown links. External links may be normal `https://` URLs.

Allowed:

```text
[AAPL profile](../entity/stock/aapl/profile.md)
https://sqlite.org/fts5.html
```

Rejected:

```text
/home/user/.strata-memory/...
file:///home/user/...
[[AAPL profile]]
```

Broken local links warn in drafts and block promotion into durable tiers unless explicitly overridden.

## 7. Promotion Flow

Promotion mutates files first, then re-indexes. SQLite is not edited directly by promotion logic.

```text
1_draft/research/foo.md
  -> 2_knowledge/research/foo.md
  -> 1_draft/_archived/research/foo.md
```

Promotion steps:

1. Validate source file, target path, frontmatter, tags, links, and room registration.
2. Create a unique operation temp directory under `0_core/tmp/`.
3. Build promoted and archived candidates in the temp directory.
4. Validate hashes, frontmatter, and links.
5. Move candidates into final vault paths.
6. Remove original draft only after final files exist.
7. Run `index.sh --target` for the promoted artifact and archived draft.
8. Write an operation log.
9. Delete temp files on success. Leave temp files on failure and print their path.

Promotion never overwrites existing target files by default. MVP supports failure plus `--new-slug`; merge and replace are deferred.

## 8. Retention

Archived drafts are retained for a configurable period.

```yaml
retention:
  archived_drafts_days: 180
  default_mode: report
```

`retention.sh` defaults to report-only. Deletion requires `--apply`.

Deletion logs are kept indefinitely:

```text
3_intelligence/report/maintenance/retention-2026-06-06.json
```

## 9. Tags, Rooms, and Profiles

### 9.1 Tags

Tags are controlled by config. Unknown tags warn in drafts and are reviewed at promotion.

`tag-review.sh` detects:

- exact case-insensitive matches
- singular/plural matches
- dash/underscore/space-normalized matches

New tags can be added to config after review.

### 9.2 Rooms

Rooms are registered in config with path patterns, descriptions, allowed statuses, and depth policy.

```yaml
rooms:
  2_knowledge:
    - path: "concept"
      description: "Foundational ideas, definitions, principles, patterns, frameworks."
      depth: "shallow"
      allowed_status:
        - verified
        - archived
    - path: "entity/stock/*"
      description: "Stock-specific knowledge keyed by ticker symbol."
      depth: "recursive"
      required_files:
        - "_meta.md"
      allowed_status:
        - verified
        - archived
```

Unregistered folders are not invalid, but they are outside the official navigation contract. They are indexed with warnings, reported by `room-review.sh`, and excluded from generated `AGENTS.md` room descriptions until registered.

### 9.3 Profiles

Profiles define default rooms, commands, and generated `AGENTS.md` sections.

```yaml
profile: "trader"
profiles:
  trader:
    tier2_rooms:
      - "concept"
      - "entity/stock/*"
      - "entity/cryptocurrency/*"
      - "research"
      - "note"
      - "preference"
  coder:
    tier2_rooms:
      - "concept"
      - "entity/project/*"
      - "entity/tool/*"
      - "research"
      - "note"
      - "preference"
```

## 10. Generated `AGENTS.md`

`AGENTS.md` is generated from templates and config, with protected manual sections.

The public repo starter lives at:

```text
docs/AGENTS_template.md
```

During install, that starter can seed the managed template tree. Runtime generation writes the final prompt to:

```text
~/.strata-memory/AGENTS.md
```

Template source:

```text
0_core/template/agents/
├── base.md
├── profile/
│   ├── coder.md
│   ├── trader.md
│   └── researcher.md
└── section/
```

User overrides:

```text
0_core/template_override/
```

Generated sections use markers:

```markdown
<!-- STRATA_GENERATED_START -->
...
<!-- STRATA_GENERATED_END -->
```

Manual sections are preserved:

```markdown
<!-- STRATA_MANUAL_START -->
project-specific instructions
<!-- STRATA_MANUAL_END -->
```

`AGENTS.md` includes concise core command references and points to full generated docs:

```text
0_core/doc/commands.md
```

Core Strata commands are namespaced, for example `strata:search`, `strata:promote`, and `strata:migrate`.

## 11. SQLite Index

SQLite is a derived index. It can be deleted and rebuilt from files.

### 11.1 Schema Direction

```sql
CREATE TABLE IF NOT EXISTS memory_index (
    id TEXT PRIMARY KEY,
    path TEXT UNIQUE NOT NULL,
    title TEXT,
    description TEXT,
    strata TEXT NOT NULL CHECK(strata IN ('1_draft', '2_knowledge', '3_intelligence', '0_core')),
    status TEXT NOT NULL CHECK(status IN ('pending', 'verified', 'archived', 'generated', 'core')),
    tags TEXT,
    sources TEXT,
    source_note TEXT,
    version INTEGER DEFAULT 1,
    last_edit_summary TEXT,
    created TEXT,
    modified TEXT,
    content TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    metadata TEXT
);
```

FTS5 indexes:

```text
title, description, content, tags
```

Ranking weights:

```text
title > description > tags > content
```

Default search excludes archived content unless requested.

### 11.2 Link Graph

```sql
CREATE TABLE links (
  source_path TEXT NOT NULL,
  target TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK(target_type IN ('local', 'url', 'unresolved')),
  link_text TEXT,
  line INTEGER,
  created_at TEXT NOT NULL,
  PRIMARY KEY (source_path, target, line)
);
```

### 11.3 Sections

The indexer extracts Markdown heading sections for snippets and future retrieval.

```sql
CREATE TABLE sections (
  path TEXT NOT NULL,
  heading TEXT NOT NULL,
  level INTEGER NOT NULL,
  start_line INTEGER NOT NULL,
  end_line INTEGER,
  content TEXT NOT NULL,
  PRIMARY KEY (path, start_line)
);
```

Whole-file FTS remains primary in MVP.

### 11.4 Schema Migrations

```text
0_core/db/schema.sql
0_core/db/migrations/001_init.sql
```

```sql
CREATE TABLE schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);
```

## 12. CLI Tools

All commands support human output and `--json`.

MVP commands:

```text
install.sh
0_core/script/init.sh
0_core/script/doctor.sh
0_core/script/config-compile.sh
0_core/script/db-migrate.sh
0_core/script/normalize.sh
0_core/script/index.sh
0_core/script/promote.sh
0_core/script/search.sh
0_core/script/tag-review.sh
0_core/script/room-review.sh
0_core/script/link-review.sh
0_core/script/agents-generate.sh
0_core/script/migration.sh
0_core/script/retention.sh
0_core/script/privacy-review.sh
```

Shared libraries:

```text
0_core/script/lib/
├── config.sh
├── frontmatter.sh
├── json.sh
├── log.sh
├── paths.sh
├── platform.sh
└── sqlite.sh
```

Each script exposes `--help` and `--json-help`. Command docs are generated from script metadata.

## 13. Dependencies

Bootstrap mode:

```text
bash 3.2
sqlite3
awk
sed
find
sort
mktemp
```

Full mode:

```text
yq
jq
```

`init.sh` checks dependencies and prints install guidance. It does not install packages automatically.

Temporary files must live under `0_core/tmp/`, using `mktemp` with a vault-local template:

```bash
mktemp -d "${STRATA_VAULT}/0_core/tmp/promote-XXXXXXXX"
```

## 14. Phase 4a Rust Core CLI

The Bash scripts are the MVP command contract and remain useful as compatibility wrappers and emergency fallbacks. Phase 4a introduces an optional compiled Rust CLI for performance-sensitive and correctness-sensitive internals, starting with indexing.

Target installed shape:

```text
0_core/bin/strata
0_core/script/index.sh
0_core/script/search.sh
0_core/script/doctor.sh
```

Shell scripts keep the public command surface stable and delegate to the Rust binary when available:

```bash
0_core/script/index.sh --full --vault ~/.strata-memory --json
0_core/bin/strata index --full --vault ~/.strata-memory --json
```

Rust migration order:

1. Implement `strata index` first, because indexing is the slowest current path.
2. Preserve `index.sh` behavior for `--target`, `--full`, `--vault`, and `--json`.
3. Use one process, one SQLite connection, one full-index transaction, and prepared statements.
4. Add stderr progress output every N files after basic parity is stable, controlled by `STRATA_INDEX_PROGRESS_EVERY` for non-interactive runs.
5. Keep Bash index behavior as a reference/fallback until fixture and real-vault parity are proven.
6. Move `search` next once index parity is stable, preserving `--query`, `--limit`, `--include-archived`, `--paths-only`, and `--json`.
7. Move mutating commands such as `promote`, `normalize`, and `retention` later.

The Rust binary is not an MVP dependency. Distribution options are:

- copy a prebuilt platform binary into `0_core/bin/strata`
- build from source with Cargo during development
- fall back to Bash scripts when no compatible binary is installed

The first Rust milestone should happen before watcher implementation, because real-time sync depends on indexing throughput and correctness.

## 15. Git and Privacy

Git is supported but not required. The private vault can be stored in a private git repo.

Default `.gitignore` should exclude:

```gitignore
0_core/db/strata.db
0_core/cache/
0_core/tmp/
0_core/test/tmp/
3_intelligence/report/scratch/
3_intelligence/report/debug/
```

`1_draft` is tracked by default in new Strata vaults because active and archived drafts are provenance.

`privacy-review.sh` warns about:

- absolute home paths
- `file://` links
- API-key-like strings
- private SSH keys
- `.env`-style secrets
- large pasted logs

## 16. Migration

Migration reads from old Agent Memory and writes into the new Strata vault. It never modifies the old memory.

```text
migration.sh --from ~/.agent-knowledge/memory --to ~/.strata-memory --section config
migration.sh --from ~/.agent-knowledge/memory --to ~/.strata-memory --section knowledge
migration.sh --from ~/.agent-knowledge/memory --to ~/.strata-memory --section intelligence
migration.sh --from ~/.agent-knowledge/memory --to ~/.strata-memory --section agents-md
migration.sh --from ~/.agent-knowledge/memory --to ~/.strata-memory --all
```

Rules:

- Do not migrate old drafts.
- Make each section idempotent.
- Do not overwrite existing target files unless explicitly requested.
- Lowercase and hyphen-normalize paths.
- Preserve display casing in metadata.
- Detect lowercase path collisions and block the affected section by default.
- Rewrite only links that can be resolved unambiguously.
- Put unmatched migrated knowledge under `_unmapped` for review.
- Write migration reports under `3_intelligence/report/migration/`.

## 17. Quality Limits

Line-count checks warn only. They do not block.

```yaml
quality:
  max_lines:
    2_knowledge:
      default: 400
      research: 1000
      entity: 800
      concept: 600
      note: 400
      preference: 300
    3_intelligence:
      skill: 400
      agent: 250
      workflow: 400
```

`SKILL.md` should stay under the skill limit. Large examples, references, and templates belong in `resource/`. Scripts are excluded from prose line limits.

## 18. Roadmap

### Phase 0: Public Engine Repo Spec and Installer

Prepare the public repo, installer, templates, schema, and docs without touching personal memory.

### Phase 1: Empty Strata Vault MVP

Create and operate a new empty `~/.strata-memory` vault with explicit indexing, promotion, search, review, generated `AGENTS.md`, and health checks.

### Phase 2: Section Migration

Migrate selected sections from `~/.agent-knowledge/memory` into `~/.strata-memory`, leaving the old memory intact.

### Phase 3: Migration Validation and Cleanup

Validate migrated content, resolve unmapped rooms, fix links/tags, and stabilize the private vault.

### Phase 4a: Rust Core CLI Foundation

Add an optional Rust `strata` binary behind the existing Bash command contract, starting with bulk indexing and preserving Bash fallback behavior.

### Phase 4: Watchers and Real-Time Sync

Add `watcher/linux.sh` and `watcher/mac.sh` only after migration validation is complete.

### Phase 5: Semantic/Vector Search

Add optional `sqlite-vec` and local embeddings after FTS5 and lifecycle behavior are stable.

### Phase 6: Workflow Runner and Richer Automation

Add workflow execution orchestration after skills, agents, and reports have stable contracts.

## 19. MVP Acceptance

Linux-only acceptance for MVP:

1. Install engine into an empty vault.
2. Initialize trader or coder profile.
3. Normalize a draft.
4. Index and search the draft.
5. Promote draft to `2_knowledge` with archived source.
6. Detect and review unknown tags.
7. Detect unregistered rooms.
8. Generate `AGENTS.md` from template/profile/manual block.
9. Run `doctor.sh` successfully.
10. Run section migration from `~/.agent-knowledge/memory` without modifying old memory.

macOS support remains a design constraint and post-MVP validation target.
