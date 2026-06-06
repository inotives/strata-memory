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

usage() {
    cat <<'USAGE'
Usage: link-review.sh [--vault PATH] [--json]

Review vault Markdown links. Broken local links warn in drafts and error in durable tiers.
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
issues_tmp=$(mktemp "${vault}/0_core/tmp/link-issues-XXXXXXXX")
trap 'rm -f "$issues_tmp"' EXIT HUP INT TERM
: > "$issues_tmp"

severity_for() {
    case "$1" in
        1_draft/*) printf '%s\n' "warn" ;;
        *) printf '%s\n' "error" ;;
    esac
}

review_markdown_links() {
    local file=$1
    local rel=$2
    local source_dir
    source_dir=$(dirname "$rel")

    awk -v rel="$rel" -v source_dir="$source_dir" -v vault="$vault" '
    function emit(kind, target, text, line) {
      printf "%s\t%s\t%s\t%s\t%d\n", rel, kind, target, text, line
    }
    {
      rest = $0
      while (match(rest, /\[[^]]+\]\([^)]+\)/)) {
        token = substr(rest, RSTART, RLENGTH)
        text = token
        sub(/^\[/, "", text)
        sub(/\]\(.*/, "", text)
        target = token
        sub(/^.*\]\(/, "", target)
        sub(/\)$/, "", target)
        emit("markdown", target, text, NR)
        rest = substr(rest, RSTART + RLENGTH)
      }
      rest = $0
      while (match(rest, /\[\[[^]]+\]\]/)) {
        token = substr(rest, RSTART, RLENGTH)
        target = token
        gsub(/^\[\[|\]\]$/, "", target)
        emit("wikilink", target, target, NR)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }' "$file"
}

find "$vault/1_draft" "$vault/2_knowledge" "$vault/3_intelligence" -type f -name '*.md' 2>/dev/null | while IFS= read -r file; do
    rel=$(strata_rel_path "$file" "$vault")
    review_markdown_links "$file" "$rel" | while IFS="$(printf '\t')" read -r path kind target text line; do
        severity=$(severity_for "$path")
        reason=
        case "$kind:$target" in
            wikilink:*) reason="wikilink_not_allowed" ;;
            markdown:file://*) reason="file_url_not_allowed" ;;
            markdown:/*) reason="absolute_path_not_allowed" ;;
            markdown:http://*|markdown:https://*) reason= ;;
            markdown:*)
                clean=${target%%#*}
                clean=${clean%%\?*}
                if [ -n "$clean" ]; then
                    source_dir=$(dirname "$path")
                    candidate="${vault}/${source_dir}/${clean}"
                    if [ ! -f "$candidate" ]; then
                        reason="broken_local_link"
                    fi
                fi
                ;;
        esac
        if [ -n "$reason" ]; then
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$severity" "$reason" "$path" "$target" "$text" "$line" >> "$issues_tmp"
        fi
    done
done

count=$(wc -l < "$issues_tmp" | awk '{print $1}')
errors=$(awk -F '\t' '$1 == "error" { count++ } END { print count + 0 }' "$issues_tmp")

if [ "$json" = true ]; then
    printf '{"ok":%s,"issue_count":%s,"error_count":%s,"issues":[' "$([ "$errors" = "0" ] && printf true || printf false)" "$count" "$errors"
    first=true
    while IFS="$(printf '\t')" read -r severity reason path target text line; do
        [ -n "$severity" ] || continue
        if [ "$first" = true ]; then first=false; else printf ','; fi
        printf '{"severity":'; strata_json_string "$severity"
        printf ',"reason":'; strata_json_string "$reason"
        printf ',"path":'; strata_json_string "$path"
        printf ',"target":'; strata_json_string "$target"
        printf ',"line":%s}' "$line"
    done < "$issues_tmp"
    printf ']}\n'
else
    if [ "$count" = "0" ]; then
        printf 'No link issues found\n'
    else
        printf 'Link issues:\n'
        awk -F '\t' '{ printf "%s %s %s:%s -> %s\n", $1, $2, $3, $6, $4 }' "$issues_tmp"
    fi
fi

[ "$errors" = "0" ] || exit 1
