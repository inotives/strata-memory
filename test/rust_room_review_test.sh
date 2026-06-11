#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-room-review-test-XXXXXXXX")
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

mkdir -p \
    "${VAULT}/2_knowledge/entity/stock/aapl/daily" \
    "${VAULT}/2_knowledge/entity/unknown/foo"

cat > "${VAULT}/2_knowledge/entity/stock/aapl/daily/2026-06-06.md" <<'EOF'
---
title: "AAPL Daily"
description: "Registered recursive room."
tags:
  - research
sources:
  - "../../../../1_draft/_archived/research/aapl.md"
---
# AAPL
EOF

cat > "${VAULT}/2_knowledge/entity/unknown/foo/page.md" <<'EOF'
---
title: "Unknown Room"
description: "Unregistered room."
tags:
  - research
sources:
  - "../../../../1_draft/_archived/research/unknown.md"
---
# Unknown
EOF

out=$("$STRATA_BIN" room-review --vault "$VAULT" --json)
assert_contains "$out" '"ok":true' "json ok"
assert_contains "$out" '"unregistered_count":1' "unregistered count"
assert_contains "$out" '"room":"2_knowledge/entity/unknown/foo"' "unknown room"

case "$out" in
    *"2_knowledge/entity/stock/aapl/daily"*) fail "registered recursive stock room should not be reported" ;;
esac

if ! "$STRATA_BIN" room-review --vault "$VAULT" >/dev/null; then
    fail "room review should be warning-only"
fi

printf 'ok - rust room review passed\n'
