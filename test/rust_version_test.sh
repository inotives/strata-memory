#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
EXPECTED_VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' "${ROOT}/src/rust/strata/Cargo.toml")

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

[ "$("$STRATA_BIN" version)" = "strata ${EXPECTED_VERSION}" ] || fail "expected human version output"
[ "$("$STRATA_BIN" version --json)" = "{\"ok\":true,\"name\":\"strata\",\"version\":\"${EXPECTED_VERSION}\"}" ] || fail "expected JSON version output"

printf 'ok - rust version passed\n'
