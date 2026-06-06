#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/paths.sh
. "${SCRIPT_DIR}/lib/paths.sh"
# shellcheck source=lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/sqlite.sh
. "${SCRIPT_DIR}/lib/sqlite.sh"

usage() {
    cat <<'USAGE'
Usage: db-migrate.sh [--vault PATH] [--json]

Apply Strata-Memory SQLite migrations into 0_core/db/strata.db.
USAGE
}

json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vault)
            STRATA_VAULT=$2
            export STRATA_VAULT
            shift 2
            ;;
        --json)
            json=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

strata_check_bootstrap_dependencies

db=$(strata_db_path)
migrations=$(strata_migrations_dir)
applied_count=0
sqlite_bin=$(strata_sqlite_bin)

mkdir -p "$(dirname "$db")"

"$sqlite_bin" "$db" < "$(strata_core)/db/schema.sql"

for migration in "${migrations}"/*.sql; do
    [ -f "$migration" ] || continue
    name=$(basename "$migration")
    version=${name%%_*}

    if strata_sqlite_has_migration "$db" "$version"; then
        continue
    fi

    case "$name" in
        *_fts5.sql)
            if ! strata_sqlite_supports_fts5; then
                printf '%s\n' "Skipping ${name}: sqlite3 was built without FTS5 support." >&2
                continue
            fi
            sqlite_bin=$(strata_sqlite_fts5_bin)
            ;;
    esac

    "$sqlite_bin" "$db" < "$migration"
    "$sqlite_bin" "$db" "INSERT INTO schema_migrations (version, applied_at) VALUES ('${version}', strftime('%Y-%m-%dT%H:%M:%SZ','now'));"
    applied_count=$((applied_count + 1))
done

if [ "$json" = true ]; then
    printf '{"ok":true,"db":"%s","applied":%s}\n' "$db" "$applied_count"
else
    printf 'Database migrated: %s (%s applied)\n' "$db" "$applied_count"
fi
