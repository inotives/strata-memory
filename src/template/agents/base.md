# Strata-Memory

Strata-Memory is a local-first three-tier memory wiki for agentic work. Numbered tier folders are load-bearing: content moves upward as it earns durability.

```text
1_draft -> 2_knowledge -> 3_intelligence
```

`0_core/` is not a tier. It holds the vault kernel: config, scripts, schema, templates, generated docs, cache, tests, and temp files.

**Main configuration:** `0_core/config/configs.yaml`

## Draft Research

Research drafts should start from the managed template at `0_core/template/draft/research-draft.md`. Preserve its frontmatter fields when creating or refining deep-research notes.

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

<!-- STRATA_GENERATED_START -->
## Structure

```text
0_core/            Kernel: config, scripts, schema, templates, docs, cache, tmp.
1_draft/           Tier 1: raw, unreviewed, ephemeral material.
2_knowledge/       Tier 2: curated, reviewed, durable knowledge.
3_intelligence/    Tier 3: skills, agents, workflows, and generated reports.
```

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
| `strata:semantic-refresh` | Rebuild local semantic embeddings when configured. |
| `strata:semantic-status` | Report semantic search readiness and fallback mode. |
| `strata:link-review` | Review invalid or broken vault links. |
| `strata:promote` | Promote drafts into knowledge or intelligence. |
| `strata:tag-review` | Review unknown or similar tags. |
| `strata:room-review` | Review unregistered rooms. |
| `strata:migrate` | Migrate selected sections from `~/.agent-knowledge/memory`. |
| `strata:agents-generate` | Generate `AGENTS.md` from templates, profile, config, and manual sections. |

Full generated command docs live at `0_core/doc/commands.md`.
<!-- STRATA_GENERATED_END -->

<!-- STRATA_MANUAL_START -->
Add vault-specific instructions here.
<!-- STRATA_MANUAL_END -->
