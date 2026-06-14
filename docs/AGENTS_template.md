# Strata-Memory

Strata-Memory is a local-first three-tier memory wiki for agentic work. Numbered tier folders are load-bearing: content moves upward as it earns durability.

```text
1_draft -> 2_knowledge -> 3_intelligence
```

`0_core/` is not a tier. It holds the vault kernel: config, scripts, schema, templates, generated docs, cache, tests, and temp files.

**Main configuration:** `0_core/config/configs.yaml`  
**Project specification:** `docs/project_spec.md`  
**Decision log:** `docs/decisions.md`  
**Implementation plan:** `docs/implementation_plan.md`

## Critical Rules

- Do not delete `~/.strata-memory`; it is the private memory vault.
- Markdown files are canonical. SQLite is a rebuildable derived index.
- No emojis in titles or bodies unless explicitly requested.
- One topic per knowledge page. Split rather than over-broaden.
- Reuse existing tags before inventing new ones.
- Use relative POSIX Markdown links for local vault references. Do not use wikilinks.
- Do not use absolute local paths or `file://` links in vault content.
- Keep responses concise unless the user asks otherwise.
- Do not assume. Surface tradeoffs and uncertainty.

## Structure

```text
0_core/            Kernel: config, scripts, schema, templates, docs, cache, tmp.
1_draft/           Tier 1: raw, unreviewed, ephemeral material.
2_knowledge/       Tier 2: curated, reviewed, durable knowledge.
3_intelligence/    Tier 3: skills, agents, workflows, and generated reports.
```

## `0_core/`

Expected installed layout:

```text
0_core/
├── config/
├── cache/
├── db/
├── doc/
├── script/
├── template/
├── template_override/
├── test/
└── tmp/
```

Index useful docs/templates, but ignore DB files, cache, temp files, and test temp data.

## `1_draft/`

Unverified working material. Drafts may be incomplete and may have empty descriptions.

Research drafts should start from the managed template at `0_core/template/draft/research-draft.md`. Preserve its frontmatter fields when creating or refining deep-research notes.

Default rooms:

```text
research/
note/
skill/
agent/
workflow/
session/
_archived/
```

Promotion archives the source draft under `_archived/`. Archived drafts are searchable only when explicitly included.

## `2_knowledge/`

Curated durable knowledge. Descriptions are required. Sources are required, but may be empty with `source_note`.

Common rooms:

```text
concept/
entity/
research/
note/
preference/
_archived/
```

Room structure is profile-driven. Entity subtrees are usually recursive, for example:

```text
entity/stock/aapl/daily/
entity/cryptocurrency/btc/daily/
entity/project/opencode/plugin/
```

Paths are lowercase. Preserve display casing in metadata.

## `3_intelligence/`

Executable and operational intelligence.

```text
skill/
agent/
workflow/
report/
_archived/
```

- `skill/`: reusable capabilities with `SKILL.md`, optional scripts/resources/tests.
- `agent/`: persona definitions.
- `workflow/`: orchestration across skills, agents, commands, and reports.
- `report/`: generated outputs with `status: generated`.

Skill scripts require an execution allowlist before automatic use.

## Promotion Flow

Promotion is file-first and index-second:

```text
1_draft/research/foo.md
  -> 2_knowledge/research/foo.md
  -> 1_draft/_archived/research/foo.md
```

Rules:

- Validate frontmatter, tags, rooms, links, and target path first.
- Use vault-local temp files under `0_core/tmp/`.
- Never overwrite an existing target by default.
- Archive the draft as provenance.
- Re-index affected files after filesystem writes.
- Treat SQLite as recoverable cache.

## Strata Commands

Core commands are namespaced in generated command tables.

Before relying on Strata search results, run `strata refresh` once per session. Re-run it after creating, editing, moving, deleting, promoting, or migrating vault files. Use plain `strata search` for repeated queries after refresh.

| Command | Usage |
|---|---|
| `strata:init` | Initialize vault structure and bootstrap config. |
| `strata:doctor` | Check vault health, dependencies, config, schema, rooms, tags, and generated files. |
| `strata:refresh` | Refresh the derived SQLite index with a full scan. |
| `strata:index` | Index target files or run a full scan. |
| `strata:search` | Search indexed memory. |
| `strata:link-review` | Review invalid or broken vault links. |
| `strata:promote` | Promote drafts into knowledge or intelligence. |
| `strata:tag-review` | Review unknown or similar tags. |
| `strata:room-review` | Review unregistered rooms. |
| `strata:migrate` | Migrate selected sections from `~/.agent-knowledge/memory`. |
| `strata:agents-generate` | Generate `AGENTS.md` from templates, profile, config, and manual sections. |

Full generated command docs live at `0_core/doc/commands.md`.

## Context-Mode Routing Rules

MANDATORY: context-mode MCP tools protect the context window. Prefer sandbox tools over raw file or shell output when processing large data.

**Think in Code:** analyze, filter, search, and parse data through context-mode tools. Print only the derived answer.

Use context-mode for:

- shell output likely over 20 lines
- file analysis
- large search results
- logs and test output
- documentation fetching and indexing
- structured data processing

Write artifacts to files. Return only the path and a concise description.
