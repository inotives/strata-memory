# Remove Archive Flows and Add Document Attribution Plan

**Status:** Proposed

## Goal

Remove the `_archived` lifecycle entirely. Promotion will create the durable
document in its target tier and delete its draft source. Deleting a document
will remain an explicit filesystem operation followed by `strata refresh`.

At the same time, add `approved_by` and `modified_by` frontmatter so durable
documents retain approval and latest-editor attribution.

## Decisions

1. No new archive files or `_archived` directories will be created.
2. `strata promote` will require `--approved-by "ACTOR"`. `ACTOR` is a
   non-empty free-text identity (for example, a name, username, or service
   identity).
3. Promotion writes the supplied actor to both `approved_by` and
   `modified_by` on the durable document because promotion is its latest
   modification.
4. New document templates include both fields. Authors update `modified_by`
   manually for direct edits, alongside `version`, `modified`, and
   `last_edit_summary`.
5. Existing documents and configurations remain readable without these new
   fields. The attribution requirement applies to newly promoted documents.
6. Legacy `_archived` files stay on disk for now but are ignored everywhere
   by Strata. Their manual cleanup and reindexing are deferred.
7. No `strata delete` command will be added: users remove the intended file
   and run `strata refresh`.

## Implementation Plan

### Promotion and indexing

1. Simplify the promotion lifecycle to validate the source, target path,
   frontmatter, target ownership, and logical document ID before changing any
   file.
2. Build only the durable target candidate. Set its promoted status and time,
   add `approved_by`, set `modified_by` to the same supplied actor, and remove
   archive-specific metadata, path generation, and archive-ID suffixes.
3. Write the durable target, then remove the source draft. If target creation
   fails, preserve the source. If source removal fails after the target is
   written, return a clear failure while preserving the durable target rather
   than attempting destructive rollback.
4. Update promotion summaries, human output, and JSON output to expose only
   the durable target and operation log. Remove archive fields and archive
   indexing calls.
5. Index only the durable target after a successful promotion in both SQLite
   and Turso flows.

### Remove archive interfaces

1. Remove the `retention` command, its lifecycle implementation, configuration
   accessor, template configuration, documentation, and test coverage.
2. Remove `search --include-archived` and its backend filtering branches.
3. Remove `archived` from generated status defaults and stop creating
   `_archived` directories in the vault layout and installer.
4. Continue accepting existing configuration that contains legacy retention
   or archive-status settings, but do not generate, document, or act on them.

### Legacy archive isolation

1. Centralize an `_archived` path exclusion and apply it before parsing or
   indexing Markdown files.
2. Apply the same exclusion to search refreshes, doctor checks, reviews, and
   status validation so legacy duplicate IDs, broken links, and archived
   statuses cannot affect active-vault health.
3. Ensure full refresh removes stale index rows for excluded legacy archive
   paths without deleting the files themselves.

### Frontmatter and agent guidance

1. Extend parsed/indexed frontmatter metadata for `approved_by` and
   `modified_by` without requiring them on legacy documents.
2. Add the fields to managed draft and durable-document templates. Template
   guidance must make clear that `modified_by` is maintained manually during
   direct edits.
3. Update the repository and generated `AGENTS.md` guidance, README, command
   documentation, and installer documentation:
   - use promote only for a new durable document;
   - pass `--approved-by` when promoting;
   - edit existing durable files directly and update `modified_by`;
   - delete files permanently and run refresh;
   - treat `_archived` as ignored legacy content.

## Verification

1. A successful promotion creates and indexes one durable target, removes the
   source draft, creates no archive file, and writes matching `approved_by`
   and `modified_by` values.
2. Missing `--approved-by`, duplicate target paths, and duplicate document IDs
   fail before the source draft is deleted.
3. A direct filesystem deletion followed by `strata refresh` removes the
   document from index and search results.
4. A legacy `_archived` file containing a duplicate ID, `archived` status, or
   broken link remains on disk but is absent from search and does not create
   doctor, review, or refresh failures. Refresh removes its former index row.
5. Run the promotion and refresh contracts against SQLite and Turso backends.
6. Confirm `strata retention` and `--include-archived` are unavailable, and
   confirm generated and repository agent instructions describe the new
   workflow.

## Out of Scope

- Deleting historic `_archived` files.
- Adding a CLI deletion command.
- Backfilling attribution fields into existing documents.
