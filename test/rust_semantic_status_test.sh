#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-semantic-status-test-XXXXXXXX")
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

human=$("$STRATA_BIN" semantic-status --vault "$VAULT")
assert_contains "$human" "Semantic search: unavailable" "human semantic unavailable"
assert_contains "$human" "Provider configured: no" "human provider status"
assert_contains "$human" "Runtime available: no" "human runtime status"
assert_contains "$human" "Vector index ready: no" "human vector status"
assert_contains "$human" "Fallback: FTS5" "human fallback"

json=$("$STRATA_BIN" semantic-status --vault "$VAULT" --json)
assert_contains "$json" '"ok":true' "json ok"
assert_contains "$json" '"semantic_available":false' "json semantic unavailable"
assert_contains "$json" '"provider_configured":false' "json provider unconfigured"
assert_contains "$json" '"runtime_available":false' "json runtime unavailable"
assert_contains "$json" '"vector_index_ready":false' "json vector not ready"
assert_contains "$json" '"fallback":"fts5"' "json fallback"

printf 'ok - rust semantic status passed\n'
