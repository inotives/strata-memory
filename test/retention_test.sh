#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/retention-test-XXXXXXXX")
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

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

mkdir -p "${VAULT}/1_draft/_archived/research"

cat > "${VAULT}/1_draft/_archived/research/old.md" <<'EOF'
---
title: "Old"
archived_at: "2020-01-01T00:00:00Z"
---
# Old
EOF

cat > "${VAULT}/1_draft/_archived/research/new.md" <<'EOF'
---
title: "New"
archived_at: "2999-01-01T00:00:00Z"
---
# New
EOF

cat > "${VAULT}/1_draft/_archived/research/missing.md" <<'EOF'
---
title: "Missing"
---
# Missing
EOF

out=$("${VAULT}/0_core/script/retention.sh" --vault "$VAULT" --json)
case "$out" in
    *'"candidate_count":1'*'"deleted_count":0'*'"kept_count":1'*'"skipped_count":1'*) ;;
    *) fail "unexpected report output: $out" ;;
esac

assert_file "${VAULT}/1_draft/_archived/research/old.md"
report="${VAULT}/3_intelligence/report/maintenance/retention-$(date -u '+%Y-%m-%d').json"
assert_file "$report"
assert_contains "$report" '"action":"candidate"'
assert_contains "$report" '"action":"kept"'
assert_contains "$report" '"action":"skipped"'

out=$("${VAULT}/0_core/script/retention.sh" --vault "$VAULT" --apply --json)
case "$out" in
    *'"candidate_count":0'*'"deleted_count":1'*'"kept_count":1'*'"skipped_count":1'*) ;;
    *) fail "unexpected apply output: $out" ;;
esac

assert_missing "${VAULT}/1_draft/_archived/research/old.md"
assert_file "${VAULT}/1_draft/_archived/research/new.md"
assert_file "${VAULT}/1_draft/_archived/research/missing.md"
assert_contains "$report" '"action":"deleted"'

printf 'ok - retention passed\n'
