#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-tag-review-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
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
STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

mkdir -p "${VAULT}/2_knowledge/concept" "${VAULT}/1_draft/note"

cat > "${VAULT}/2_knowledge/concept/tagged.md" <<'EOF'
---
title: "Tagged"
description: "Used for tag review."
tags:
  - Research
  - unknown-tag
sources:
  - "../../1_draft/_archived/research/tagged.md"
---
# Tagged

Body.
EOF

cat > "${VAULT}/1_draft/note/valid.md" <<'EOF'
---
title: "Valid"
description: ""
tags:
  - research
---
# Valid
EOF

out=$("$STRATA_BIN" tag-review --vault "$VAULT" --json)
assert_contains "$out" '"ok":true' "json ok"
assert_contains "$out" '"unknown_count":2' "unknown count"
assert_contains "$out" '"tag":"Research"' "case tag"
assert_contains "$out" '"similar":"research"' "similar tag"
assert_contains "$out" '"tag":"unknown-tag"' "unknown tag"

if ! "$STRATA_BIN" tag-review --vault "$VAULT" >/dev/null; then
    fail "tag review should be warning-only"
fi

printf 'ok - rust tag review passed\n'
