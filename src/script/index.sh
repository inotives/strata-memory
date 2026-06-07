#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/frontmatter.sh
. "${SCRIPT_DIR}/lib/frontmatter.sh"
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
Usage: index.sh [--target FILE | --full] [--vault PATH] [--json]

Index Strata-Memory Markdown files into SQLite.
USAGE
}

target=
full=false
json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)
            target=$2
            shift 2
            ;;
        --full)
            full=true
            shift
            ;;
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

if [ -n "$target" ] && [ "$full" = true ]; then
    strata_log_error "use either --target or --full, not both"
    exit 2
fi

if [ -z "$target" ] && [ "$full" = false ]; then
    full=true
fi

vault=$(strata_vault)
db=$(strata_db_path)
sqlite_bin=$(strata_sqlite_bin)

rust_bin="${vault}/0_core/bin/strata"
if [ "${STRATA_INDEX_BASH_FALLBACK:-}" != "1" ] && [ -x "$rust_bin" ]; then
    args=(index --vault "$vault")
    if [ "$full" = true ]; then
        args+=(--full)
    fi
    if [ -n "$target" ]; then
        args+=(--target "$target")
    fi
    if [ "$json" = true ]; then
        args+=(--json)
    fi
    exec "$rust_bin" "${args[@]}"
fi

"${SCRIPT_DIR}/db-migrate.sh" --vault "$vault" >/dev/null

indexed=0

json_array_or_empty() {
    local value=$1
    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '[]'
    fi
}

abs_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$(pwd)" "$1" ;;
    esac
}

index_one() {
    local file=$1
    local abs
    local rel
    local strata
    local status
    local id
    local title
    local description
    local tags
    local sources
    local source_note
    local version
    local last_edit_summary
    local created
    local modified
    local content
    local hash
    local rowid
    local sql_tmp

    [ -f "$file" ] || return 0
    case "$file" in
        *.md) ;;
        *) return 0 ;;
    esac

    abs=$(abs_path "$file")
    rel=$(strata_rel_path "$abs" "$vault")
    strata=$(strata_detect_strata "$rel") || return 0

    case "$rel" in
        0_core/cache/*|0_core/tmp/*|0_core/test/tmp/*|0_core/db/*) return 0 ;;
    esac

    status=$(strata_extract_scalar "$abs" status)
    if [ -z "$status" ]; then
        case "$rel" in
            3_intelligence/report/*) status=generated ;;
            *) status=$(strata_default_status "$strata" "$rel") ;;
        esac
    fi
    case "$status" in
        pending|verified|archived|generated|core) ;;
        *)
            strata_log_error "invalid status for ${rel}: ${status}"
            exit 1
            ;;
    esac

    id=$(strata_extract_scalar "$abs" id)
    [ -n "$id" ] || id=$(strata_make_id "$rel")
    title=$(strata_extract_scalar "$abs" title)
    [ -n "$title" ] || title=$(basename -- "$abs" .md | sed 's/-/ /g')
    description=$(strata_extract_scalar "$abs" description)
    tags=$(strata_extract_array_json "$abs" tags)
    sources=$(strata_extract_array_json "$abs" sources)
    tags=$(json_array_or_empty "$tags")
    sources=$(json_array_or_empty "$sources")
    source_note=$(strata_extract_scalar "$abs" source_note)
    version=$(strata_extract_scalar "$abs" version)
    [ -n "$version" ] || version=1
    last_edit_summary=$(strata_extract_scalar "$abs" last_edit_summary)
    created=$(strata_extract_scalar "$abs" created)
    modified=$(strata_extract_scalar "$abs" modified)
    content=$(sed -n '1,$p' "$abs")
    hash=$(cksum "$abs" | awk '{print $1 ":" $2}')

    sql_tmp=$(mktemp "${vault}/0_core/tmp/index-sql-XXXXXXXX")
    {
        printf 'BEGIN;\n'
        printf 'DELETE FROM memory_fts WHERE rowid IN (SELECT rowid FROM memory_index WHERE path = %s);\n' "$(strata_sqlite_quote "$rel")"
        printf 'DELETE FROM memory_index WHERE path = %s;\n' "$(strata_sqlite_quote "$rel")"
        printf 'DELETE FROM links WHERE source_path = %s;\n' "$(strata_sqlite_quote "$rel")"
        printf 'DELETE FROM sections WHERE path = %s;\n' "$(strata_sqlite_quote "$rel")"
        printf 'INSERT INTO memory_index (id,path,title,description,strata,status,tags,sources,source_note,version,last_edit_summary,created,modified,content,content_hash,metadata) VALUES ('
        printf '%s,' "$(strata_sqlite_quote "$id")"
        printf '%s,' "$(strata_sqlite_quote "$rel")"
        printf '%s,' "$(strata_sqlite_quote "$title")"
        printf '%s,' "$(strata_sqlite_quote "$description")"
        printf '%s,' "$(strata_sqlite_quote "$strata")"
        printf '%s,' "$(strata_sqlite_quote "$status")"
        printf '%s,' "$(strata_sqlite_quote "$tags")"
        printf '%s,' "$(strata_sqlite_quote "$sources")"
        printf '%s,' "$(strata_sqlite_quote "$source_note")"
        printf '%s,' "$version"
        printf '%s,' "$(strata_sqlite_quote "$last_edit_summary")"
        printf '%s,' "$(strata_sqlite_quote "$created")"
        printf '%s,' "$(strata_sqlite_quote "$modified")"
        printf '%s,' "$(strata_sqlite_quote "$content")"
        printf '%s,' "$(strata_sqlite_quote "$hash")"
        printf '%s);\n' "$(strata_sqlite_quote "{}")"
        printf 'INSERT INTO memory_fts(rowid,title,description,tags,content) SELECT rowid,title,description,tags,content FROM memory_index WHERE path = %s;\n' "$(strata_sqlite_quote "$rel")"
        awk -v source="$rel" '
        function q(s) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }
        {
          line = $0
          rest = line
          while (match(rest, /\[[^]]+\]\([^)]+\)/)) {
            token = substr(rest, RSTART, RLENGTH)
            text = token
            sub(/^\[/, "", text)
            sub(/\]\(.*/, "", text)
            target = token
            sub(/^.*\]\(/, "", target)
            sub(/\)$/, "", target)
            type = "local"
            if (target ~ /^https?:\/\//) type = "url"
            if (target ~ /^\[\[/) type = "unresolved"
            printf "INSERT OR REPLACE INTO links (source_path,target,target_type,link_text,line,created_at) VALUES (%s,%s,%s,%s,%d,strftime(\047%%Y-%%m-%%dT%%H:%%M:%%SZ\047,\047now\047));\n", q(source), q(target), q(type), q(text), NR
            rest = substr(rest, RSTART + RLENGTH)
          }
        }' "$abs"
        awk -v path="$rel" '
        function q(s) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }
        /^#{1,6}[ \t]+/ {
          if (heading != "") {
            printf "INSERT OR REPLACE INTO sections (path,heading,level,start_line,end_line,content) VALUES (%s,%s,%d,%d,%d,%s);\n", q(path), q(heading), level, start, NR - 1, q(content)
          }
          line = $0
          match(line, /^#+/)
          level = RLENGTH
          heading = line
          sub(/^#+[ \t]+/, "", heading)
          start = NR
          content = line "\n"
          next
        }
        heading != "" { content = content $0 "\n" }
        END {
          if (heading != "") {
            printf "INSERT OR REPLACE INTO sections (path,heading,level,start_line,end_line,content) VALUES (%s,%s,%d,%d,%d,%s);\n", q(path), q(heading), level, start, NR, q(content)
          }
        }' "$abs"
        printf 'COMMIT;\n'
    } > "$sql_tmp"

    "$sqlite_bin" "$db" < "$sql_tmp"
    rm -f "$sql_tmp"
    indexed=$((indexed + 1))
}

if [ "$full" = true ]; then
    list_tmp=$(mktemp "${vault}/0_core/tmp/index-list-XXXXXXXX")
    find "$vault/0_core/doc" "$vault/1_draft" "$vault/2_knowledge" "$vault/3_intelligence" -type f -name '*.md' 2>/dev/null > "$list_tmp"
    while IFS= read -r file; do
        index_one "$file"
    done < "$list_tmp"

    stale_sql=$(mktemp "${vault}/0_core/tmp/index-stale-XXXXXXXX")
    {
        printf 'DELETE FROM links WHERE source_path NOT IN ('
        while IFS= read -r file; do abs=$(abs_path "$file"); rel=$(strata_rel_path "$abs" "$vault"); printf '%s,' "$(strata_sqlite_quote "$rel")"; done < "$list_tmp" \
          | sed 's/,$//'
        printf ');\n'
        printf 'DELETE FROM sections WHERE path NOT IN ('
        while IFS= read -r file; do abs=$(abs_path "$file"); rel=$(strata_rel_path "$abs" "$vault"); printf '%s,' "$(strata_sqlite_quote "$rel")"; done < "$list_tmp" \
          | sed 's/,$//'
        printf ');\n'
        printf 'DELETE FROM memory_fts WHERE rowid IN (SELECT rowid FROM memory_index WHERE path NOT IN ('
        while IFS= read -r file; do abs=$(abs_path "$file"); rel=$(strata_rel_path "$abs" "$vault"); printf '%s,' "$(strata_sqlite_quote "$rel")"; done < "$list_tmp" \
          | sed 's/,$//'
        printf '));\n'
        printf 'DELETE FROM memory_index WHERE path NOT IN ('
        while IFS= read -r file; do abs=$(abs_path "$file"); rel=$(strata_rel_path "$abs" "$vault"); printf '%s,' "$(strata_sqlite_quote "$rel")"; done < "$list_tmp" \
          | sed 's/,$//'
        printf ');\n'
    } > "$stale_sql"
    "$sqlite_bin" "$db" < "$stale_sql"
    rm -f "$stale_sql"
    rm -f "$list_tmp"
elif [ -n "$target" ]; then
    index_one "$target"
fi

if [ "$json" = true ]; then
    printf '{"ok":true,"indexed":%s}\n' "$indexed"
else
    printf 'Indexed %s file(s)\n' "$indexed"
fi
