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

usage() {
    cat <<'USAGE'
Usage: retention.sh [--vault PATH] [--apply] [--json]

Report archived draft files older than retention.archived_drafts_days.
Deletion requires --apply.
USAGE
}

json=false
apply=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vault) STRATA_VAULT=$2; export STRATA_VAULT; shift 2 ;;
        --apply) apply=true; shift ;;
        --json) json=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf '%s\n' "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

vault=$(strata_vault)
core=$(strata_core)
tmp_dir="${core}/tmp"
archive_root="${vault}/1_draft/_archived"
report_dir="${vault}/3_intelligence/report/maintenance"

mkdir -p "$tmp_dir" "$report_dir"

records_tmp=$(mktemp "${tmp_dir}/retention-records-XXXXXXXX")
report_tmp=$(mktemp "${tmp_dir}/retention-report-XXXXXXXX.json")
trap 'rm -f "$records_tmp" "$report_tmp"' EXIT HUP INT TERM
: > "$records_tmp"

days=$(strata_config_retention_archived_drafts_days)
case "$days" in
    ''|*[!0-9]*)
        printf 'Invalid retention.archived_drafts_days: %s\n' "$days" >&2
        exit 1
        ;;
esac

now_epoch=$(date -u '+%s')
generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
today=$(date -u '+%Y-%m-%d')
report_path="${report_dir}/retention-${today}.json"

timestamp_epoch() {
    local timestamp=$1
    date -u -d "$timestamp" '+%s' 2>/dev/null || return 1
}

record() {
    local action=$1
    local rel=$2
    local archived_at=$3
    local age_days=$4
    local reason=$5
    printf '%s\t%s\t%s\t%s\t%s\n' "$action" "$rel" "$archived_at" "$age_days" "$reason" >> "$records_tmp"
}

if [ -d "$archive_root" ]; then
    find "$archive_root" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r file; do
        rel=$(strata_rel_path "$file" "$vault")
        archived_at=$(strata_extract_scalar "$file" archived_at)
        if [ -z "$archived_at" ]; then
            record skipped "$rel" "" "" "missing_archived_at"
            continue
        fi

        if ! archived_epoch=$(timestamp_epoch "$archived_at"); then
            record skipped "$rel" "$archived_at" "" "invalid_archived_at"
            continue
        fi

        age_days=$(( (now_epoch - archived_epoch) / 86400 ))
        if [ "$age_days" -lt "$days" ]; then
            record kept "$rel" "$archived_at" "$age_days" "within_retention"
            continue
        fi

        if [ "$apply" = true ]; then
            rm -f "$file"
            record deleted "$rel" "$archived_at" "$age_days" "expired"
        else
            record candidate "$rel" "$archived_at" "$age_days" "expired"
        fi
    done
fi

candidate_count=$(awk -F '\t' '$1 == "candidate" { count++ } END { print count + 0 }' "$records_tmp")
deleted_count=$(awk -F '\t' '$1 == "deleted" { count++ } END { print count + 0 }' "$records_tmp")
kept_count=$(awk -F '\t' '$1 == "kept" { count++ } END { print count + 0 }' "$records_tmp")
skipped_count=$(awk -F '\t' '$1 == "skipped" { count++ } END { print count + 0 }' "$records_tmp")

{
    printf '{\n'
    printf '  "ok": true,\n'
    printf '  "generated_at": '; strata_json_string "$generated_at"; printf ',\n'
    printf '  "mode": '; strata_json_string "$([ "$apply" = true ] && printf apply || printf report)"; printf ',\n'
    printf '  "retention_days": %s,\n' "$days"
    printf '  "candidate_count": %s,\n' "$candidate_count"
    printf '  "deleted_count": %s,\n' "$deleted_count"
    printf '  "kept_count": %s,\n' "$kept_count"
    printf '  "skipped_count": %s,\n' "$skipped_count"
    printf '  "records": [\n'
    first=true
    while IFS="$(printf '\t')" read -r action path archived_at age_days reason; do
        [ -n "$action" ] || continue
        if [ "$first" = true ]; then first=false; else printf ',\n'; fi
        printf '    {"action":'; strata_json_string "$action"
        printf ',"path":'; strata_json_string "$path"
        printf ',"archived_at":'; strata_json_string "$archived_at"
        if [ -n "$age_days" ]; then
            printf ',"age_days":%s' "$age_days"
        else
            printf ',"age_days":null'
        fi
        printf ',"reason":'; strata_json_string "$reason"
        printf '}'
    done < "$records_tmp"
    printf '\n  ]\n'
    printf '}\n'
} > "$report_tmp"

mv "$report_tmp" "$report_path"

if [ "$json" = true ]; then
    printf '{"ok":true,"report":'
    strata_json_string "$(strata_rel_path "$report_path" "$vault")"
    printf ',"mode":'
    strata_json_string "$([ "$apply" = true ] && printf apply || printf report)"
    printf ',"candidate_count":%s,"deleted_count":%s,"kept_count":%s,"skipped_count":%s}\n' \
        "$candidate_count" "$deleted_count" "$kept_count" "$skipped_count"
else
    printf 'Retention %s complete: %s candidate, %s deleted, %s kept, %s skipped\n' \
        "$([ "$apply" = true ] && printf apply || printf report)" \
        "$candidate_count" "$deleted_count" "$kept_count" "$skipped_count"
    printf 'Report: %s\n' "$(strata_rel_path "$report_path" "$vault")"
fi
