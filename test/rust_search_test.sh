#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-search-test-XXXXXXXX")
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

assert_contains() {
    local haystack=$1
    local needle=$2
    local label=$3
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "$label: expected '$needle' in '$haystack'" ;;
    esac
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

mkdir -p "${VAULT}/2_knowledge/concept" "${VAULT}/1_draft/_archived/research"

cat > "${VAULT}/2_knowledge/concept/alpha-title.md" <<'EOF'
---
title: "Alpha"
description: "Title match should rank first."
strata: "2_knowledge"
status: "verified"
tags:
  - search
sources:
  - "../../1_draft/_archived/research/alpha-title.md"
version: 1
---
# Topic

Short body.
EOF

cat > "${VAULT}/2_knowledge/concept/body-match.md" <<'EOF'
---
title: "Body Match"
description: "Contains the term only in body content."
strata: "2_knowledge"
status: "verified"
tags:
  - search
sources:
  - "../../1_draft/_archived/research/body-match.md"
version: 1
---
# Topic

This paragraph mentions alpha in the body.
EOF

cat > "${VAULT}/1_draft/_archived/research/archived-alpha.md" <<'EOF'
---
title: "Archived Alpha"
description: ""
status: "archived"
---
# Archived

alpha archived content
EOF

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

"$STRATA_BIN" index --vault "$VAULT" --full >/dev/null

first=$("$STRATA_BIN" search --vault "$VAULT" --query alpha --paths-only --limit 1)
assert_eq "$first" "2_knowledge/concept/alpha-title.md" "title ranking"

default_results=$("$STRATA_BIN" search --vault "$VAULT" --query alpha --paths-only --limit 10)
case "$default_results" in
    *"1_draft/_archived/research/archived-alpha.md"*) fail "archived result should be excluded by default" ;;
esac

archived_results=$("$STRATA_BIN" search --vault "$VAULT" --query alpha --paths-only --include-archived --limit 10)
assert_contains "$archived_results" "1_draft/_archived/research/archived-alpha.md" "include archived"

human=$("$STRATA_BIN" search --vault "$VAULT" --query alpha --limit 2)
assert_contains "$human" "[alpha]" "snippet"

json=$("$STRATA_BIN" search --vault "$VAULT" --query alpha --json --limit 1)
assert_contains "$json" '"ok":true' "json ok"
assert_contains "$json" '"refreshed":false' "json not refreshed"
assert_contains "$json" '"requested_mode":"fts"' "json requested fts"
assert_contains "$json" '"mode":"fts"' "json mode fts"
assert_contains "$json" '"warnings":[]' "json no warnings"
assert_contains "$json" '"results":[' "json results"
assert_contains "$json" '"path":"2_knowledge/concept/alpha-title.md"' "json path"

hybrid_err="${VAULT}/0_core/tmp/hybrid.err"
hybrid=$("$STRATA_BIN" search --vault "$VAULT" --query alpha --hybrid --limit 1 2>"$hybrid_err")
assert_contains "$hybrid" "2_knowledge/concept/alpha-title.md" "hybrid fallback results"
assert_contains "$(cat "$hybrid_err")" "semantic search unavailable; returned FTS5 results" "hybrid warning"

hybrid_json=$("$STRATA_BIN" search --vault "$VAULT" --query alpha --hybrid --json --limit 1)
assert_contains "$hybrid_json" '"requested_mode":"hybrid"' "hybrid json requested mode"
assert_contains "$hybrid_json" '"mode":"fts"' "hybrid json actual mode"
assert_contains "$hybrid_json" '"warnings":["semantic search unavailable; returned FTS5 results"]' "hybrid json warning"
assert_contains "$hybrid_json" '"path":"2_knowledge/concept/alpha-title.md"' "hybrid json result"

cat > "${VAULT}/2_knowledge/concept/fresh.md" <<'EOF'
---
title: "Fresh"
description: "Freshness policy test."
strata: "2_knowledge"
status: "verified"
tags:
  - search
sources:
  - "../../1_draft/_archived/research/fresh.md"
version: 1
---
# Fresh

omega fresh content
EOF

stale_results=$("$STRATA_BIN" search --vault "$VAULT" --query omega --paths-only --limit 10 || true)
case "$stale_results" in
    *"2_knowledge/concept/fresh.md"*) fail "plain search should not refresh implicitly" ;;
esac

refreshed=$("$STRATA_BIN" search --vault "$VAULT" --query omega --refresh --paths-only --limit 10)
assert_contains "$refreshed" "2_knowledge/concept/fresh.md" "refresh search indexes new file"

refresh_json=$("$STRATA_BIN" search --vault "$VAULT" --query omega --refresh --json --limit 1)
assert_contains "$refresh_json" '"refreshed":true' "refresh json metadata"
assert_contains "$refresh_json" '"requested_mode":"fts"' "refresh json requested mode"
assert_contains "$refresh_json" '"mode":"fts"' "refresh json actual mode"
assert_contains "$refresh_json" '"indexed":' "refresh json indexed count"
assert_contains "$refresh_json" '"path":"2_knowledge/concept/fresh.md"' "refresh json path"

refresh_cmd_json=$("$STRATA_BIN" refresh --vault "$VAULT" --json)
assert_contains "$refresh_cmd_json" '"ok":true' "refresh command json ok"
assert_contains "$refresh_cmd_json" '"indexed":' "refresh command indexed count"

MISSING_VAULT=$(mktemp -d "${TMP_ROOT}/rust-search-missing-db-XXXXXXXX")
"${ROOT}/install.sh" --vault "$MISSING_VAULT" >/dev/null
missing_out=$("$STRATA_BIN" search --vault "$MISSING_VAULT" --query alpha 2>&1 || true)
assert_contains "$missing_out" "run strata refresh first" "missing db guidance"

printf 'ok - rust search passed\n'
