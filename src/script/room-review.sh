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
Usage: room-review.sh [--vault PATH] [--json]

Report files located outside registered room patterns.
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
patterns_tmp=$(mktemp "${vault}/0_core/tmp/room-patterns-XXXXXXXX")
unknown_tmp=$(mktemp "${vault}/0_core/tmp/room-unknown-XXXXXXXX")
trap 'rm -f "$patterns_tmp" "$unknown_tmp"' EXIT HUP INT TERM

strata_config_room_patterns > "$patterns_tmp"
: > "$unknown_tmp"

matches_pattern() {
    local room=$1
    local pattern=$2
    case "$pattern" in
        *'*')
            prefix=${pattern%\*}
            case "$room" in
                "$prefix"*) return 0 ;;
            esac
            ;;
        *)
            case "$room" in
                "$pattern"|"$pattern"/*) return 0 ;;
            esac
            ;;
    esac
    return 1
}

review_file() {
    local file=$1
    local rel
    local room
    local pattern

    rel=$(strata_rel_path "$file" "$vault")
    case "$rel" in
        1_draft/*|2_knowledge/*|3_intelligence/*) ;;
        *) return 0 ;;
    esac

    room=$(dirname "$rel")
    while IFS= read -r pattern; do
        [ -n "$pattern" ] || continue
        if matches_pattern "$room" "$pattern"; then
            return 0
        fi
    done < "$patterns_tmp"

    printf '%s\t%s\n' "$rel" "$room" >> "$unknown_tmp"
}

find "$vault/1_draft" "$vault/2_knowledge" "$vault/3_intelligence" -type f -name '*.md' 2>/dev/null | while IFS= read -r file; do
    review_file "$file"
done

count=$(wc -l < "$unknown_tmp" | awk '{print $1}')
if [ "$json" = true ]; then
    printf '{"ok":true,"unregistered_count":%s,"unregistered":[' "$count"
    first=true
    while IFS="$(printf '\t')" read -r path room; do
        [ -n "$path" ] || continue
        if [ "$first" = true ]; then first=false; else printf ','; fi
        printf '{"path":'; strata_json_string "$path"
        printf ',"room":'; strata_json_string "$room"
        printf '}'
    done < "$unknown_tmp"
    printf ']}\n'
else
    if [ "$count" = "0" ]; then
        printf 'No unregistered rooms found\n'
    else
        printf 'Unregistered rooms:\n'
        awk -F '\t' '{ printf "%s: %s\n", $1, $2 }' "$unknown_tmp"
    fi
fi
