#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-index-backend-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null
STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

sqlite=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json)
case "$sqlite" in
    *'"backend":"sqlite"'*) ;;
    *) fail "expected SQLite backend metadata: $sqlite" ;;
esac

sed 's/backend: "sqlite"/backend: "turso"/' \
    "${VAULT}/0_core/config/configs.yaml" > "${VAULT}/0_core/config/configs.yaml.turso"
mv "${VAULT}/0_core/config/configs.yaml.turso" "${VAULT}/0_core/config/configs.yaml"

TURSO_MIGRATE=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json)
case "$TURSO_MIGRATE" in
    *'"backend":"turso"'*'"experimental":true'*'"applied":2'*) ;;
    *) fail "expected Turso migrations: $TURSO_MIGRATE" ;;
esac
[ -f "${VAULT}/0_core/db/strata-turso.db" ] || fail "expected Turso database file"

TURSO_SECOND=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json)
case "$TURSO_SECOND" in
    *'"backend":"turso"'*'"applied":0'*) ;;
    *) fail "expected idempotent Turso migrations: $TURSO_SECOND" ;;
esac

for command in \
    "refresh" \
    "search --query test" \
    "semantic-refresh" \
    "semantic-status"
do
    if "$STRATA_BIN" $command --vault "$VAULT" >/dev/null 2>"${VAULT}/0_core/tmp/backend.err"; then
        fail "expected Turso rejection for: $command"
    fi
    grep -F 'index backend turso is not available yet; set index.backend: sqlite and run strata refresh' \
        "${VAULT}/0_core/tmp/backend.err" >/dev/null 2>&1 || fail "expected explicit Turso error for: $command"
done

if doctor=$("$STRATA_BIN" doctor --vault "$VAULT" --json 2>/dev/null); then
    fail "expected doctor to reject unavailable Turso backend"
fi
case "$doctor" in
    *'"backend":"turso"'*'"experimental":true'*'"name":"index_backend"'*) ;;
    *) fail "expected experimental Turso doctor output: $doctor" ;;
esac

printf 'ok - rust index backend passed\n'
