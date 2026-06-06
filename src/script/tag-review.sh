#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/config.sh
. "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/frontmatter.sh
. "${SCRIPT_DIR}/lib/frontmatter.sh"
# shellcheck source=lib/json.sh
. "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/log.sh
. "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=lib/paths.sh
. "${SCRIPT_DIR}/lib/paths.sh"

usage() {
    cat <<'USAGE'
Usage: tag-review.sh [--vault PATH] [--json]

Review Markdown frontmatter tags against configured allowed tags.
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
allowed_tmp=$(mktemp "${vault}/0_core/tmp/tag-allowed-XXXXXXXX")
unknown_tmp=$(mktemp "${vault}/0_core/tmp/tag-unknown-XXXXXXXX")
trap 'rm -f "$allowed_tmp" "$unknown_tmp"' EXIT HUP INT TERM

strata_config_allowed_tags > "$allowed_tmp"
: > "$unknown_tmp"

normalize_tag() {
    printf '%s' "$1" | tr '[:upper:]_ ' '[:lower:]--' | sed 's/-*$//' | sed 's/s$//'
}

review_tag() {
    local file=$1
    local rel=$2
    local tag=$3
    local tag_lc
    local tag_norm
    local allowed
    local allowed_lc
    local allowed_norm
    local similar=""

    tag_lc=$(printf '%s' "$tag" | tr '[:upper:]' '[:lower:]')
    tag_norm=$(normalize_tag "$tag")

    while IFS= read -r allowed; do
        [ -n "$allowed" ] || continue
        allowed_lc=$(printf '%s' "$allowed" | tr '[:upper:]' '[:lower:]')
        allowed_norm=$(normalize_tag "$allowed")
        if [ "$tag" = "$allowed" ]; then
            return 0
        fi
        if [ "$tag_lc" = "$allowed_lc" ] || [ "$tag_norm" = "$allowed_norm" ]; then
            similar=$allowed
        fi
    done < "$allowed_tmp"

    printf '%s\t%s\t%s\n' "$rel" "$tag" "$similar" >> "$unknown_tmp"
    return 0
}

find "$vault/1_draft" "$vault/2_knowledge" "$vault/3_intelligence" -type f -name '*.md' 2>/dev/null | while IFS= read -r file; do
    rel=$(strata_rel_path "$file" "$vault")
    awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && /^tags:/ { in_tags = 1; next }
    in_tags && /^[ ][ ]-/ {
      value = $0
      sub(/^[ ][ ]-[ ]*/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      next
    }
    in_tags && /^[^ ]/ { exit }
    ' "$file" | while IFS= read -r tag; do
        review_tag "$file" "$rel" "$tag"
    done
done

count=$(wc -l < "$unknown_tmp" | awk '{print $1}')
if [ "$json" = true ]; then
    printf '{"ok":true,"unknown_count":%s,"unknown":[' "$count"
    first=true
    while IFS="$(printf '\t')" read -r path tag similar; do
        [ -n "$path" ] || continue
        if [ "$first" = true ]; then first=false; else printf ','; fi
        printf '{"path":'; strata_json_string "$path"
        printf ',"tag":'; strata_json_string "$tag"
        printf ',"similar":'; strata_json_string "$similar"
        printf '}'
    done < "$unknown_tmp"
    printf ']}\n'
else
    if [ "$count" = "0" ]; then
        printf 'No unknown tags found\n'
    else
        printf 'Unknown tags:\n'
        awk -F '\t' '{ if ($3 != "") printf "%s: %s (similar: %s)\n", $1, $2, $3; else printf "%s: %s\n", $1, $2 }' "$unknown_tmp"
    fi
fi
