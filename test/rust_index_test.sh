#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-index-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local actual=$1
    local expected=$2
    local label=$3
    [ "$actual" = "$expected" ] || fail "$label: expected '$expected', got '$actual'"
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

mkdir -p "${VAULT}/1_draft/research" "${VAULT}/1_draft/_archived/research" "${VAULT}/2_knowledge/research"

cat > "${VAULT}/2_knowledge/research/sqlite-fts.md" <<'EOF'
---
id: "mem_index_001"
title: "SQLite FTS"
description: "Explains FTS indexing."
strata: "2_knowledge"
status: "verified"
tags:
  - sqlite
  - search
sources:
  - "../../1_draft/_archived/research/sqlite-fts.md"
version: 1
created: "2026-06-06"
modified: "2026-06-06"
---
# Overview

SQLite FTS5 powers local search.

See [SQLite docs](https://sqlite.org/fts5.html) and [draft](../../1_draft/_archived/research/sqlite-fts.md).

## Details

Weighted ranking prefers title matches.
EOF

cat > "${VAULT}/1_draft/research/raw.md" <<'EOF'
---
title: "Raw Draft"
description: ""
tags:
  - research
---
# Draft

Unverified note.
EOF

cat > "${VAULT}/1_draft/_archived/research/old.md" <<'EOF'
---
title: "Old Draft"
description: ""
---
# Old

Archived draft.
EOF

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

"$STRATA_BIN" index --vault "$VAULT" --target "${VAULT}/2_knowledge/research/sqlite-fts.md" >/dev/null
DB="${VAULT}/0_core/db/strata.db"

count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '2_knowledge/research/sqlite-fts.md';")
assert_eq "$count" "1" "target row"

fts_count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_fts WHERE memory_fts MATCH 'FTS5';")
assert_eq "$fts_count" "1" "fts row"

url_links=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM links WHERE source_path = '2_knowledge/research/sqlite-fts.md' AND target_type = 'url';")
assert_eq "$url_links" "1" "url link"

local_links=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM links WHERE source_path = '2_knowledge/research/sqlite-fts.md' AND target_type = 'local';")
assert_eq "$local_links" "1" "local link"

section_count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM sections WHERE path = '2_knowledge/research/sqlite-fts.md';")
assert_eq "$section_count" "2" "sections"

"$STRATA_BIN" index --vault "$VAULT" --full >/dev/null
raw_count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '1_draft/research/raw.md' AND status = 'pending';")
assert_eq "$raw_count" "1" "full scan draft"

archived_count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '1_draft/_archived/research/old.md' AND status = 'archived';")
assert_eq "$archived_count" "1" "archived status"

rm "${VAULT}/1_draft/research/raw.md"
"$STRATA_BIN" index --vault "$VAULT" --full >/dev/null
stale_count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '1_draft/research/raw.md';")
assert_eq "$stale_count" "0" "stale removal"

cat > "${VAULT}/1_draft/research/moved.md" <<'EOF'
---
id: "moved-note"
title: "Moved Note"
description: ""
tags:
  - research
---
# Moved

Moved note content.
EOF
"$STRATA_BIN" index --vault "$VAULT" --full >/dev/null
mkdir -p "${VAULT}/1_draft/note"
mv "${VAULT}/1_draft/research/moved.md" "${VAULT}/1_draft/note/moved.md"
"$STRATA_BIN" index --vault "$VAULT" --full >/dev/null
moved_count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE id = 'moved-note' AND path = '1_draft/note/moved.md';")
assert_eq "$moved_count" "1" "moved file id reindex"
old_moved_count=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '1_draft/research/moved.md';")
assert_eq "$old_moved_count" "0" "moved file stale path removed"

printf 'ok - rust index passed\n'
