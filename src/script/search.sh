#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/json.sh
. "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/log.sh
. "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=lib/paths.sh
. "${SCRIPT_DIR}/lib/paths.sh"
# shellcheck source=lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/sqlite.sh
. "${SCRIPT_DIR}/lib/sqlite.sh"

usage() {
    cat <<'USAGE'
Usage: search.sh --query TEXT [--vault PATH] [--limit N] [--include-archived] [--paths-only] [--json]

Search indexed Strata-Memory files with SQLite FTS5.
USAGE
}

query=
limit=10
include_archived=false
paths_only=false
json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --query|-q)
            query=$2
            shift 2
            ;;
        --vault)
            STRATA_VAULT=$2
            export STRATA_VAULT
            shift 2
            ;;
        --limit)
            limit=$2
            shift 2
            ;;
        --include-archived)
            include_archived=true
            shift
            ;;
        --paths-only)
            paths_only=true
            shift
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
            if [ -z "$query" ]; then
                query=$1
                shift
            else
                printf '%s\n' "Unknown argument: $1" >&2
                usage >&2
                exit 2
            fi
            ;;
    esac
done

[ -n "$query" ] || { usage >&2; exit 2; }

case "$limit" in
    ''|*[!0-9]*) strata_log_error "limit must be a positive integer"; exit 2 ;;
esac

db=$(strata_db_path)
[ -f "$db" ] || { strata_log_error "database not found; run index.sh first"; exit 1; }

sqlite_bin=$(strata_sqlite_bin)
where_status=""
if [ "$include_archived" = false ]; then
    where_status="AND memory_index.status <> 'archived'"
fi

query_lit=$(strata_sqlite_quote "$query")

if [ "$paths_only" = true ]; then
    sql="SELECT memory_index.path
FROM memory_fts
JOIN memory_index ON memory_fts.rowid = memory_index.rowid
WHERE memory_fts MATCH ${query_lit} ${where_status}
ORDER BY bm25(memory_fts, 8.0, 4.0, 2.0, 1.0)
LIMIT ${limit};"
    "$sqlite_bin" "$db" "$sql"
    exit 0
fi

sql="SELECT memory_index.path || char(9) ||
       ifnull(memory_index.title,'') || char(9) ||
       memory_index.status || char(9) ||
       printf('%.6f', bm25(memory_fts, 8.0, 4.0, 2.0, 1.0)) || char(9) ||
       replace(replace(snippet(memory_fts, 3, '[', ']', '...', 12), char(10), ' '), char(9), ' ')
FROM memory_fts
JOIN memory_index ON memory_fts.rowid = memory_index.rowid
WHERE memory_fts MATCH ${query_lit} ${where_status}
ORDER BY bm25(memory_fts, 8.0, 4.0, 2.0, 1.0)
LIMIT ${limit};"

if [ "$json" = true ]; then
    printf '{"ok":true,"query":'
    strata_json_string "$query"
    printf ',"results":['
    first=true
    "$sqlite_bin" "$db" "$sql" | while IFS="$(printf '\t')" read -r path title status rank snippet; do
        if [ "$first" = true ]; then
            first=false
        else
            printf ','
        fi
        printf '{"path":'
        strata_json_string "$path"
        printf ',"title":'
        strata_json_string "$title"
        printf ',"status":'
        strata_json_string "$status"
        printf ',"rank":%s,"snippet":' "$rank"
        strata_json_string "$snippet"
        printf '}'
    done
    printf ']}\n'
else
    "$sqlite_bin" "$db" "$sql" | while IFS="$(printf '\t')" read -r path title status rank snippet; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$title" "$status" "$rank" "$snippet"
    done
fi
