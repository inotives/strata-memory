#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-db-migrate-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

"$STRATA_BIN" db-migrate --vault "$VAULT" >/dev/null

DB="${VAULT}/0_core/db/strata.db"
[ -f "$DB" ] || fail "expected database file"

SQLITE_BIN=/usr/bin/sqlite3
if [ ! -x "$SQLITE_BIN" ]; then
    SQLITE_BIN=$(command -v sqlite3)
fi

tables=$("$SQLITE_BIN" "$DB" "SELECT name FROM sqlite_master WHERE type IN ('table','virtual table') ORDER BY name;")
for table in links memory_index schema_migrations sections semantic_embeddings semantic_models; do
    case "$tables" in
        *"$table"*) ;;
        *) printf 'not ok - expected table %s\n%s\n' "$table" "$tables" >&2; exit 1 ;;
    esac
done

migration_count=$("$SQLITE_BIN" "$DB" "SELECT count(*) FROM schema_migrations WHERE version = '001';")
[ "$migration_count" = "1" ] || fail "expected migration 001 to be recorded"

fts_count=$("$SQLITE_BIN" "$DB" "SELECT count(*) FROM schema_migrations WHERE version = '002';")
[ "$fts_count" = "1" ] || fail "expected FTS5 migration to be recorded"

semantic_count=$("$SQLITE_BIN" "$DB" "SELECT count(*) FROM schema_migrations WHERE version = '003';")
[ "$semantic_count" = "1" ] || fail "expected semantic foundation migration to be recorded"

second=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json 2>/dev/null)
case "$second" in
    *'"ok":true'*'"backend":"sqlite"'*'"applied":0'*) ;;
    *) printf 'not ok - expected idempotent migration\n%s\n' "$second" >&2; exit 1 ;;
esac

sed 's/backend: "sqlite"/backend: "turso"/' \
    "${VAULT}/0_core/config/configs.yaml" > "${VAULT}/0_core/config/configs.yaml.turso"
mv "${VAULT}/0_core/config/configs.yaml.turso" "${VAULT}/0_core/config/configs.yaml"
turso=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json)
case "$turso" in
    *'"backend":"turso"'*'"experimental":true'*'"applied":3'*) ;;
    *) fail "expected Turso migration output: $turso" ;;
esac
[ -f "${VAULT}/0_core/db/strata-turso.db" ] || fail "expected Turso database file"

printf 'ok - rust db migration passed\n'
