#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/search-test-XXXXXXXX")
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

"${VAULT}/0_core/script/index.sh" --vault "$VAULT" --full >/dev/null

first=$("${VAULT}/0_core/script/search.sh" --vault "$VAULT" --query alpha --paths-only --limit 1)
assert_eq "$first" "2_knowledge/concept/alpha-title.md" "title ranking"

default_results=$("${VAULT}/0_core/script/search.sh" --vault "$VAULT" --query alpha --paths-only --limit 10)
case "$default_results" in
    *"1_draft/_archived/research/archived-alpha.md"*) fail "archived result should be excluded by default" ;;
esac

archived_results=$("${VAULT}/0_core/script/search.sh" --vault "$VAULT" --query alpha --paths-only --include-archived --limit 10)
assert_contains "$archived_results" "1_draft/_archived/research/archived-alpha.md" "include archived"

human=$("${VAULT}/0_core/script/search.sh" --vault "$VAULT" --query alpha --limit 2)
assert_contains "$human" "[alpha]" "snippet"

json=$("${VAULT}/0_core/script/search.sh" --vault "$VAULT" --query alpha --json --limit 1)
assert_contains "$json" '"ok":true' "json ok"
assert_contains "$json" '"results":[' "json results"
assert_contains "$json" '"path":"2_knowledge/concept/alpha-title.md"' "json path"

printf 'ok - search passed\n'
