#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-doctor-test-XXXXXXXX")
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

"$STRATA_BIN" db-migrate --vault "$VAULT" >/dev/null
"$STRATA_BIN" agents-generate --vault "$VAULT" >/dev/null

out=$("$STRATA_BIN" doctor --vault "$VAULT" --json)
assert_contains "$out" '"ok":true' "healthy ok"
assert_contains "$out" '"backend":"sqlite"' "sqlite backend"
assert_contains "$out" '"experimental":false' "stable backend"
assert_contains "$out" '"name":"index_backend"' "index backend check"
assert_contains "$out" '"name":"migration_001"' "migration 001"
assert_contains "$out" '"name":"tag_review"' "tag review"
assert_contains "$out" '"name":"db_writable"' "db writable"
assert_contains "$out" '"name":"agents"' "agents"
assert_contains "$out" '"name":"status_review"' "status review"

cp "${VAULT}/0_core/config/configs.yaml" "${VAULT}/0_core/config/configs.yaml.sqlite"
sed 's/backend: "sqlite"/backend: "turso"/' \
    "${VAULT}/0_core/config/configs.yaml.sqlite" > "${VAULT}/0_core/config/configs.yaml"
if out=$("$STRATA_BIN" doctor --vault "$VAULT" --json 2>/dev/null); then
    fail "expected doctor to reject unavailable Turso backend"
fi
assert_contains "$out" '"backend":"turso"' "Turso backend"
assert_contains "$out" '"experimental":true' "experimental backend"
assert_contains "$out" '"name":"index_backend"' "Turso backend check"
mv "${VAULT}/0_core/config/configs.yaml.sqlite" "${VAULT}/0_core/config/configs.yaml"

mkdir -p "${VAULT}/1_draft/research" "${VAULT}/2_knowledge/research"
cat > "${VAULT}/1_draft/research/invalid-status.md" <<'EOF'
---
title: "Invalid Status"
description: ""
status: "pending-review"
---
# Invalid Status
EOF

if out=$("$STRATA_BIN" doctor --vault "$VAULT" --json 2>/dev/null); then
    fail "expected doctor to fail on invalid status"
fi
assert_contains "$out" '"ok":false' "invalid status not ok"
assert_contains "$out" '"name":"status_review"' "status review failure"
assert_contains "$out" '"status":"error"' "error status"

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

if out=$("$STRATA_BIN" doctor --vault "$VAULT" --json 2>/dev/null); then
    fail "expected doctor to fail on durable broken link"
fi
assert_contains "$out" '"ok":false' "broken link not ok"
assert_contains "$out" '"name":"link_review"' "link review failure"
assert_contains "$out" '"status":"error"' "link error status"

printf 'ok - rust doctor passed\n'
