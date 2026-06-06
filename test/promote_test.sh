#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/promote-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_file() {
    [ -f "$1" ] || fail "expected file: $1"
}

assert_missing() {
    [ ! -e "$1" ] || fail "expected missing: $1"
}

assert_contains() {
    local file=$1
    local needle=$2
    grep -F "$needle" "$file" >/dev/null 2>&1 || fail "expected '$needle' in $file"
}

assert_eq() {
    local actual=$1
    local expected=$2
    local label=$3
    [ "$actual" = "$expected" ] || fail "$label: expected '$expected', got '$actual'"
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null
mkdir -p "${VAULT}/1_draft/research" "${VAULT}/2_knowledge/research"

cat > "${VAULT}/1_draft/research/sqlite-fts.md" <<'EOF'
---
id: "mem_promote_001"
title: "SQLite FTS"
description: "Promotable draft."
status: "pending"
tags:
  - research
version: 1
created: "2026-06-06"
---
# SQLite FTS

Draft body.
EOF

out=$("${VAULT}/0_core/script/promote.sh" --vault "$VAULT" --source "${VAULT}/1_draft/research/sqlite-fts.md" --to 2_knowledge --json)
case "$out" in
    *'"ok":true'*) ;;
    *) fail "expected json promote success: $out" ;;
esac

target="${VAULT}/2_knowledge/research/sqlite-fts.md"
archive="${VAULT}/1_draft/_archived/research/sqlite-fts.md"
assert_file "$target"
assert_file "$archive"
assert_missing "${VAULT}/1_draft/research/sqlite-fts.md"
assert_contains "$target" 'strata: "2_knowledge"'
assert_contains "$target" 'status: "verified"'
assert_contains "$target" 'sources:'
assert_contains "$target" '1_draft/_archived/research/sqlite-fts.md'
assert_contains "$target" 'promoted_at: "'
assert_contains "$archive" 'status: "archived"'
assert_contains "$archive" 'archived_from: "1_draft/research/sqlite-fts.md"'

DB="${VAULT}/0_core/db/strata.db"
target_index=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '2_knowledge/research/sqlite-fts.md' AND status = 'verified';")
assert_eq "$target_index" "1" "target indexed"
archive_index=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '1_draft/_archived/research/sqlite-fts.md' AND status = 'archived';")
assert_eq "$archive_index" "1" "archive indexed"

cat > "${VAULT}/2_knowledge/research/conflict.md" <<'EOF'
---
title: "Existing Conflict"
description: "Existing target."
status: "verified"
tags:
  - research
sources:
  - "../../1_draft/_archived/research/existing.md"
---
# Existing
EOF

cat > "${VAULT}/1_draft/research/conflict.md" <<'EOF'
---
title: "Duplicate"
description: "Should fail because target exists."
status: "pending"
tags:
  - research
---
# Duplicate
EOF

if "${VAULT}/0_core/script/promote.sh" --vault "$VAULT" --source "${VAULT}/1_draft/research/conflict.md" --to 2_knowledge >/dev/null 2>&1; then
    fail "expected overwrite promotion to fail"
fi
assert_file "${VAULT}/1_draft/research/conflict.md"

"${VAULT}/0_core/script/promote.sh" --vault "$VAULT" --source "${VAULT}/1_draft/research/conflict.md" --to 2_knowledge --new-slug duplicate-note >/dev/null
assert_file "${VAULT}/2_knowledge/research/duplicate-note.md"
assert_file "${VAULT}/1_draft/_archived/research/conflict.md"

printf 'ok - promote passed\n'
