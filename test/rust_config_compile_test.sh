#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-config-compile-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

out=$("$STRATA_BIN" config-compile --vault "$VAULT" --json)
case "$out" in
    *'"ok":true'*'"profile":"coder"'*) ;;
    *) fail "expected json success output, got: $out" ;;
esac

CACHE="${VAULT}/0_core/cache/config.compiled.json"
[ -f "$CACHE" ] || fail "expected cache file"

[ "$(jq -r '.profile' "$CACHE")" = "coder" ] || fail "expected coder profile"
[ "$(jq -r '.rooms[] | select(.pattern == "2_knowledge/entity/project/*") | .depth' "$CACHE")" = "recursive" ] || fail "expected project room"
[ "$(jq -r '.profiles.coder.tier2_rooms[] | select(. == "entity/tool/*")' "$CACHE")" = "entity/tool/*" ] || fail "expected coder tool room"

cp "${VAULT}/0_core/config/configs.yaml" "${VAULT}/0_core/config/configs.yaml.bak"
sed 's/- research/- Research/' "${VAULT}/0_core/config/configs.yaml.bak" > "${VAULT}/0_core/config/configs.yaml"

if "$STRATA_BIN" config-compile --vault "$VAULT" >/dev/null 2>"${VAULT}/0_core/tmp/config-compile.err"; then
    fail "expected uppercase tag validation failure"
fi

grep -F 'tags.allowed values must be lowercase tokens' "${VAULT}/0_core/tmp/config-compile.err" >/dev/null 2>&1 || fail "expected lowercase validation error"

printf 'ok - rust config compile passed\n'
