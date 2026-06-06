#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/doctor-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack=$1
    local needle=$2
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "expected '$needle' in '$haystack'" ;;
    esac
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null
"${VAULT}/0_core/script/db-migrate.sh" --vault "$VAULT" >/dev/null
"${VAULT}/0_core/script/agents-generate.sh" --vault "$VAULT" >/dev/null

out=$("${VAULT}/0_core/script/doctor.sh" --vault "$VAULT" --json)
assert_contains "$out" '"ok":true'
assert_contains "$out" '"name":"migration_001"'
assert_contains "$out" '"name":"tag_review"'
assert_contains "$out" '"name":"agents"'

mkdir -p "${VAULT}/2_knowledge/research"
cat > "${VAULT}/2_knowledge/research/broken.md" <<'EOF'
---
title: "Broken"
description: "Broken durable link."
tags:
  - research
sources: []
---
# Broken

[missing](missing.md)
EOF

if out=$("${VAULT}/0_core/script/doctor.sh" --vault "$VAULT" --json 2>/dev/null); then
    fail "expected doctor to fail on durable broken link"
fi

assert_contains "$out" '"ok":false'
assert_contains "$out" '"name":"link_review"'
assert_contains "$out" '"status":"error"'

printf 'ok - doctor passed\n'
