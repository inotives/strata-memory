#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-init-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_dir() {
    [ -d "$1" ] || fail "expected directory: $1"
}

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

out=$("$STRATA_BIN" init --vault "$VAULT" --json)
case "$out" in
    *'"ok":true'*'"vault":'*) ;;
    *) fail "expected json success output, got: $out" ;;
esac

assert_dir "${VAULT}/0_core/config"
assert_dir "${VAULT}/0_core/cache"
assert_dir "${VAULT}/0_core/db/sqlite/migrations"
assert_dir "${VAULT}/0_core/db/turso/migrations"
assert_dir "${VAULT}/0_core/doc"
assert_dir "${VAULT}/0_core/script/lib"
assert_dir "${VAULT}/0_core/template"
assert_dir "${VAULT}/0_core/template_override"
assert_dir "${VAULT}/0_core/test/tmp"
assert_dir "${VAULT}/0_core/tmp"
assert_dir "${VAULT}/1_draft/research"
assert_dir "${VAULT}/1_draft/note"
assert_dir "${VAULT}/1_draft/skill"
assert_dir "${VAULT}/1_draft/agent"
assert_dir "${VAULT}/1_draft/workflow"
assert_dir "${VAULT}/1_draft/session"
assert_dir "${VAULT}/1_draft/_archived"
assert_dir "${VAULT}/2_knowledge/concept"
assert_dir "${VAULT}/2_knowledge/entity"
assert_dir "${VAULT}/2_knowledge/research"
assert_dir "${VAULT}/2_knowledge/note"
assert_dir "${VAULT}/2_knowledge/preference"
assert_dir "${VAULT}/2_knowledge/_archived"
assert_dir "${VAULT}/3_intelligence/skill"
assert_dir "${VAULT}/3_intelligence/agent"
assert_dir "${VAULT}/3_intelligence/workflow"
assert_dir "${VAULT}/3_intelligence/report"
assert_dir "${VAULT}/3_intelligence/_archived"

printf 'ok - rust init passed\n'
