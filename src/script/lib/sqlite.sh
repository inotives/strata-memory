#!/usr/bin/env bash

strata_sqlite_bin() {
    if [ -n "${STRATA_SQLITE:-}" ]; then
        printf '%s\n' "$STRATA_SQLITE"
        return 0
    fi

    if [ -x /usr/bin/sqlite3 ]; then
        printf '%s\n' /usr/bin/sqlite3
        return 0
    fi

    command -v sqlite3
}

strata_sqlite_fts5_bin() {
    local candidate

    if [ -n "${STRATA_SQLITE:-}" ] && [ -x "$STRATA_SQLITE" ]; then
        if "$STRATA_SQLITE" ':memory:' "CREATE VIRTUAL TABLE strata_fts5_check USING fts5(content);" >/dev/null 2>&1; then
            printf '%s\n' "$STRATA_SQLITE"
            return 0
        fi
    fi

    for candidate in /usr/bin/sqlite3 "$(command -v sqlite3 2>/dev/null || true)"; do
        [ -n "$candidate" ] || continue
        [ -x "$candidate" ] || continue
        if "$candidate" ':memory:' "CREATE VIRTUAL TABLE strata_fts5_check USING fts5(content);" >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

strata_sqlite_exec() {
    local db=$1
    local sql=$2
    "$(strata_sqlite_bin)" "$db" "$sql"
}

strata_sqlite_has_migration() {
    local db=$1
    local version=$2
    local found

    found=$("$(strata_sqlite_bin)" "$db" "SELECT version FROM schema_migrations WHERE version = '${version}' LIMIT 1;" 2>/dev/null || true)
    [ "$found" = "$version" ]
}

strata_sqlite_supports_fts5() {
    strata_sqlite_fts5_bin >/dev/null 2>&1
}
