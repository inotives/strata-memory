#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/config.sh
. "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/frontmatter.sh
. "${SCRIPT_DIR}/lib/frontmatter.sh"
# shellcheck source=lib/json.sh
. "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/paths.sh
. "${SCRIPT_DIR}/lib/paths.sh"
# shellcheck source=lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/sqlite.sh
. "${SCRIPT_DIR}/lib/sqlite.sh"

usage() {
    cat <<'USAGE'
Usage: doctor.sh [--vault PATH] [--json]

Check vault health without mutating files.
USAGE
}

json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vault) STRATA_VAULT=$2; export STRATA_VAULT; shift 2 ;;
        --json) json=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf '%s\n' "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

vault=$(strata_vault)
core=$(strata_core)
tmp_dir="${core}/tmp"
mkdir -p "$tmp_dir"

checks_tmp=$(mktemp "${tmp_dir}/doctor-checks-XXXXXXXX")
trap 'rm -f "$checks_tmp"' EXIT HUP INT TERM
: > "$checks_tmp"

record() {
    local status=$1
    local name=$2
    local message=$3
    printf '%s\t%s\t%s\n' "$status" "$name" "$message" >> "$checks_tmp"
}

run_capture() {
    local output=$1
    shift
    "$@" > "$output" 2>&1
}

if strata_check_bootstrap_dependencies > "${tmp_dir}/doctor-bootstrap.out" 2>&1; then
    record pass bootstrap_dependencies "bootstrap dependencies are available"
else
    record error bootstrap_dependencies "$(sed -n '1p' "${tmp_dir}/doctor-bootstrap.out")"
fi
rm -f "${tmp_dir}/doctor-bootstrap.out"

if strata_check_full_dependencies > "${tmp_dir}/doctor-full.out" 2>&1; then
    record pass full_dependencies "full-mode dependencies are available"
else
    record warn full_dependencies "$(sed -n '1p' "${tmp_dir}/doctor-full.out")"
fi
rm -f "${tmp_dir}/doctor-full.out"

for dir in \
    "$core/config" \
    "$core/cache" \
    "$core/db" \
    "$core/script" \
    "$core/template" \
    "$tmp_dir" \
    "$vault/1_draft" \
    "$vault/2_knowledge" \
    "$vault/3_intelligence"
do
    if [ -d "$dir" ]; then
        record pass directory "$(strata_rel_path "$dir" "$vault") exists"
    else
        record error directory "$(strata_rel_path "$dir" "$vault") is missing"
    fi
done

if strata_config_exists; then
    record pass config "0_core/config/configs.yaml exists"
    profile=$(strata_config_profile)
    if [ -n "$profile" ]; then
        record pass profile "active profile is ${profile}"
    else
        record error profile "active profile is missing"
    fi
else
    record error config "0_core/config/configs.yaml is missing"
fi

cache=$(strata_config_cache_path)
if [ -f "$cache" ]; then
    record pass config_cache "0_core/cache/config.compiled.json exists"
else
    record warn config_cache "0_core/cache/config.compiled.json is missing; run config-compile.sh when jq and yq are available"
fi

db=$(strata_db_path)
if [ -f "$db" ]; then
    record pass database "0_core/db/strata.db exists"
    sqlite_bin=$(strata_sqlite_bin)
    if "$sqlite_bin" "$db" "SELECT 1 FROM schema_migrations LIMIT 1;" >/dev/null 2>&1; then
        record pass schema "schema_migrations is readable"
        if strata_sqlite_has_migration "$db" 001; then
            record pass migration_001 "migration 001 is applied"
        else
            record error migration_001 "migration 001 is not applied"
        fi
        if strata_sqlite_supports_fts5; then
            if strata_sqlite_has_migration "$db" 002; then
                record pass migration_002 "FTS5 migration 002 is applied"
            else
                record error migration_002 "SQLite supports FTS5 but migration 002 is not applied"
            fi
        else
            record warn migration_002 "SQLite FTS5 is unavailable; FTS5 migration is skipped"
        fi
    else
        record error schema "schema_migrations is not readable"
    fi
else
    record error database "0_core/db/strata.db is missing; run db-migrate.sh"
fi

review_out=$(mktemp "${tmp_dir}/doctor-review-XXXXXXXX")
if run_capture "$review_out" "${SCRIPT_DIR}/tag-review.sh" --vault "$vault" --json; then
    tag_count=$(sed -n 's/^.*"unknown_count":\([0-9][0-9]*\).*$/\1/p' "$review_out")
    [ -n "$tag_count" ] || tag_count=0
    if [ "$tag_count" = "0" ]; then
        record pass tag_review "no unknown tags"
    else
        record warn tag_review "${tag_count} unknown or similar tags found"
    fi
else
    record error tag_review "tag-review.sh failed"
fi

if run_capture "$review_out" "${SCRIPT_DIR}/room-review.sh" --vault "$vault" --json; then
    room_count=$(sed -n 's/^.*"unregistered_count":\([0-9][0-9]*\).*$/\1/p' "$review_out")
    [ -n "$room_count" ] || room_count=0
    if [ "$room_count" = "0" ]; then
        record pass room_review "no unregistered rooms"
    else
        record warn room_review "${room_count} unregistered rooms found"
    fi
else
    record error room_review "room-review.sh failed"
fi

if run_capture "$review_out" "${SCRIPT_DIR}/link-review.sh" --vault "$vault" --json; then
    link_count=$(sed -n 's/^.*"issue_count":\([0-9][0-9]*\).*$/\1/p' "$review_out")
    [ -n "$link_count" ] || link_count=0
    if [ "$link_count" = "0" ]; then
        record pass link_review "no link issues"
    else
        record warn link_review "${link_count} draft link warnings found"
    fi
else
    error_count=$(sed -n 's/^.*"error_count":\([0-9][0-9]*\).*$/\1/p' "$review_out")
    [ -n "$error_count" ] || error_count=1
    record error link_review "${error_count} durable link errors found"
fi
rm -f "$review_out"

agents="${vault}/AGENTS.md"
if [ -f "$agents" ]; then
    if grep -F '<!-- STRATA_GENERATED_START -->' "$agents" >/dev/null 2>&1 &&
       grep -F '<!-- STRATA_MANUAL_START -->' "$agents" >/dev/null 2>&1; then
        record pass agents "AGENTS.md exists with generated and manual markers"
    else
        record warn agents "AGENTS.md exists but generated/manual markers are incomplete"
    fi
else
    record error agents "AGENTS.md is missing; run agents-generate.sh"
fi

errors=$(awk -F '\t' '$1 == "error" { count++ } END { print count + 0 }' "$checks_tmp")
warnings=$(awk -F '\t' '$1 == "warn" { count++ } END { print count + 0 }' "$checks_tmp")
passes=$(awk -F '\t' '$1 == "pass" { count++ } END { print count + 0 }' "$checks_tmp")
ok=$([ "$errors" = "0" ] && printf true || printf false)

if [ "$json" = true ]; then
    printf '{"ok":%s,"passes":%s,"warnings":%s,"errors":%s,"checks":[' "$ok" "$passes" "$warnings" "$errors"
    first=true
    while IFS="$(printf '\t')" read -r status name message; do
        [ -n "$status" ] || continue
        if [ "$first" = true ]; then first=false; else printf ','; fi
        printf '{"status":'; strata_json_string "$status"
        printf ',"name":'; strata_json_string "$name"
        printf ',"message":'; strata_json_string "$message"
        printf '}'
    done < "$checks_tmp"
    printf ']}\n'
else
    printf 'Strata doctor: %s pass, %s warning, %s error\n' "$passes" "$warnings" "$errors"
    awk -F '\t' '{ printf "%s %s - %s\n", $1, $2, $3 }' "$checks_tmp"
fi

[ "$errors" = "0" ] || exit 1
