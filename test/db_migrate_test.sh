#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/db-migrate-test-XXXXXXXX")

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null
"${VAULT}/0_core/script/db-migrate.sh" --vault "$VAULT" >/dev/null

DB="${VAULT}/0_core/db/strata.db"
[ -f "$DB" ] || fail "expected database file"

SQLITE_BIN=/usr/bin/sqlite3
if [ ! -x "$SQLITE_BIN" ]; then
    SQLITE_BIN=$(command -v sqlite3)
fi

tables=$("$SQLITE_BIN" "$DB" "SELECT name FROM sqlite_master WHERE type IN ('table','virtual table') ORDER BY name;")
for table in links memory_index schema_migrations sections; do
    case "$tables" in
        *"$table"*) ;;
        *) printf 'not ok - expected table %s\n%s\n' "$table" "$tables" >&2; exit 1 ;;
    esac
done

migration_count=$("$SQLITE_BIN" "$DB" "SELECT count(*) FROM schema_migrations WHERE version = '001';")
[ "$migration_count" = "1" ] || fail "expected migration 001 to be recorded"

if /usr/bin/sqlite3 ':memory:' "CREATE VIRTUAL TABLE strata_fts5_check USING fts5(content);" >/dev/null 2>&1; then
    fts_count=$("$SQLITE_BIN" "$DB" "SELECT count(*) FROM schema_migrations WHERE version = '002';")
    [ "$fts_count" = "1" ] || fail "expected FTS5 migration to be recorded"
else
    fts_count=$("$SQLITE_BIN" "$DB" "SELECT count(*) FROM schema_migrations WHERE version = '002';")
    [ "$fts_count" = "0" ] || fail "expected FTS5 migration to be skipped without FTS5 support"
fi

second=$("${VAULT}/0_core/script/db-migrate.sh" --vault "$VAULT" --json 2>/dev/null)
case "$second" in
    *'"applied":0'*) ;;
    *) printf 'not ok - expected idempotent migration\n%s\n' "$second" >&2; exit 1 ;;
esac

printf 'ok - db migration passed\n'
