# Handoff: Phase 2 Migration

Date: 2026-06-07
Branch: `feature/section-migration`

## Goal

Continue Phase 2 migration from legacy Agent Memory at `~/.agent-knowledge/memory` into the new Strata vault at `~/.strata-memory`, without modifying the legacy memory.

Use the `handoff` note together with:

- `docs/project_spec.md`
- `docs/implementation_plan.md`
- `docs/decisions.md`
- `src/script/migration.sh`
- `test/migration_test.sh`

## Current Repo State

Last committed migration commits on `feature/section-migration`:

- `a1f0d42 Add section migration command`
- `02e747f Harden legacy knowledge migration mapping`
- `39f7021 Harden entity migration mapping`
- `ea31c4b Harden migration reporting and metadata`

Uncommitted changes remain in:

- `src/script/migration.sh`
- `test/migration_test.sh`

Those uncommitted changes add:

- status sanitization for migrated copies, e.g. legacy `status: durable` becomes Strata-valid `status: "verified"`
- atomic migration report writes through `0_core/tmp`
- sparse long-run progress output every 100 candidates
- batched indexing: migrate writes first, then one `index.sh --full`
- fixture coverage for legacy invalid status

Before the filesystem became read-only, both focused migration tests and the full suite passed with these uncommitted changes.

## Real Vault State

The real target vault was initialized:

```bash
./install.sh --vault ~/.strata-memory
~/.strata-memory/0_core/script/db-migrate.sh --vault ~/.strata-memory
~/.strata-memory/0_core/script/agents-generate.sh --vault ~/.strata-memory
```

Initial doctor was OK with warnings only:

- missing `yq`
- missing compiled config cache

Real migration progress:

- `config`: completed cleanly and idempotently
  - latest clean rerun: `written_count: 0`, `existing_count: 9`, `warning_count: 0`
- `knowledge`: completed cleanly and idempotently
  - latest clean rerun: `written_count: 0`, `existing_count: 673`, `skipped_count: 127`, `warning_count: 0`
- `intelligence`: completed cleanly and idempotently
  - latest clean rerun: `written_count: 0`, `existing_count: 303`, `warning_count: 0`
- `agents-md`: migrated one file, but final full indexing hit SQLite lock/filesystem problems before final validation

Important real-data fix already applied to the real vault:

- Two migrated config files had invalid legacy statuses and were manually repaired in the target vault:
  - `2_knowledge/_unmapped/config/rules/convert-md-to-html.md`: `durable` -> `verified`
  - `2_knowledge/_unmapped/config/templates/research-draft-template.md`: legacy `pending-review ...` line -> `verified`

The uncommitted migration status-sanitizer should make this automatic in future reruns.

## Blocker

The machine filesystem remounted root as read-only:

```text
/dev/mapper/vgmint-root on / type ext4 (ro,nosuid,nodev,relatime,errors=remount-ro)
```

Observed failures:

- write test under `~/.strata-memory/0_core/db` failed with `Read-only file system`
- SQLite reported stale lock / disk I/O errors
- derived DB rebuild could not complete

Do not continue writes until `/` is read-write again.

## Next Steps

After the OS/filesystem is repaired or rebooted:

1. Verify repo state:

   ```bash
   git status --short --branch
   ```

2. Rerun tests for the uncommitted hardening changes:

   ```bash
   rtk bash -n install.sh src/script/*.sh src/script/lib/*.sh test/*.sh
   rtk bash test/migration_test.sh
   ```

3. Run the full suite if time allows.

4. Commit the uncommitted hardening changes:

   ```bash
   git add src/script/migration.sh test/migration_test.sh
   git commit -m "Harden migration status and reporting"
   ```

5. Repair/rebuild the derived index in the real vault:

   ```bash
   rm -f ~/.strata-memory/0_core/db/strata.db ~/.strata-memory/0_core/db/strata.db-journal
   ~/.strata-memory/0_core/script/db-migrate.sh --vault ~/.strata-memory
   ~/.strata-memory/0_core/script/index.sh --vault ~/.strata-memory --full --json
   ```

6. Rerun final validation:

   ```bash
   ~/.strata-memory/0_core/script/doctor.sh --vault ~/.strata-memory --json
   ~/.strata-memory/0_core/script/tag-review.sh --vault ~/.strata-memory --json
   ~/.strata-memory/0_core/script/room-review.sh --vault ~/.strata-memory --json
   ~/.strata-memory/0_core/script/link-review.sh --vault ~/.strata-memory --json
   ~/.strata-memory/0_core/script/privacy-review.sh --vault ~/.strata-memory --json
   ```

7. Rerun `agents-md` migration if needed:

   ```bash
   ~/.strata-memory/0_core/script/migration.sh --from ~/.agent-knowledge/memory --to ~/.strata-memory --section agents-md --json
   ```

## Notes For The Next Agent

- Do not modify or delete `~/.agent-knowledge/memory`.
- `0_core/db/strata.db` is derived and may be rebuilt.
- Reports live under `~/.strata-memory/3_intelligence/report/migration/`.
- Long migration runs now emit progress every 100 candidates after the uncommitted patch.
- Use `context-mode` tools for summarizing large reports.
- Suggested skills: `handoff` if handing off again, `diagnose` if SQLite/filesystem issues continue.
