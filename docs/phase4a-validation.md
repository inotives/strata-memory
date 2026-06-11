# Phase 4a Rust Core CLI Validation

**Date:** 2026-06-08

Phase 4a introduced an optional Rust CLI at `0_core/bin/strata` behind the then-existing Bash command contract. That wrapper/fallback state has since been superseded by the Rust runtime migration.

## Implemented Commands

- `strata index`
- `strata search`
- `strata link-review`

Installed commands now run directly through `0_core/bin/strata`:

- `0_core/bin/strata index`
- `0_core/bin/strata search`
- `0_core/bin/strata link-review`

Rust full-index progress is written to stderr. Non-interactive progress can be controlled with `STRATA_INDEX_PROGRESS_EVERY=N`; use `0` to disable it.

## Real-Vault Copy Validation

Validation ran against a temporary copy of `~/.strata-memory`; the source vault was not indexed or otherwise mutated during the temp validation.

Known source data issue fixed afterward in the actual vault:

- `1_draft/research/2026-06-07--ai-dev-tools-comparison.md`
- changed `status: pending-review` to `status: pending`

Temp validation results:

```text
installed_binary=yes
indexed=999
index_elapsed=13.27s
memory_rows=999
links=603
sections=17134
fts_rows=999
link_review=ok, issue_count=0, error_count=0
doctor=ok, passes=24, warnings=1, errors=0
```

The one doctor warning was expected for the temporary install:

```text
config_cache: 0_core/cache/config.compiled.json is missing
```

Search sanity for `stock` returned expected trading skill paths:

```text
3_intelligence/skill/trading/stock-init-profile/skill.md
3_intelligence/skill/trading/stock-market-close-summary/skill.md
3_intelligence/skill/trading/stock-fetch-close-price/skill.md
```

## Sample Bash vs Rust Comparison

An 81-file real-vault sample produced matching counts and search results:

```text
bash_elapsed=168.94s
rust_elapsed=13.47s
memory=81
links=345
sections=770
fts=81
stock search count=5
research search count=8
```

The Rust path is therefore ready for review as an optional accelerator while Bash fallback remains available.
