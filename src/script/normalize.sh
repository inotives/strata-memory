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

usage() {
    cat <<'USAGE'
Usage: normalize.sh --target FILE [--vault PATH] [--check] [--json]

Normalize constrained Markdown frontmatter for a Strata-Memory file.
Durable tiers require a non-empty description.
USAGE
}

target=
json=false
check=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)
            target=$2
            shift 2
            ;;
        --vault)
            STRATA_VAULT=$2
            export STRATA_VAULT
            shift 2
            ;;
        --check)
            check=true
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
            printf '%s\n' "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[ -n "$target" ] || { usage >&2; exit 2; }
[ -f "$target" ] || { strata_log_error "target not found: $target"; exit 1; }

vault=$(strata_vault)
case "$target" in
    /*) abs=$target ;;
    *) abs=$(CDPATH= cd -- "$(dirname -- "$target")" && pwd)/$(basename -- "$target") ;;
esac
rel=$(strata_rel_path "$abs" "$vault")
strata=$(strata_detect_strata "$rel") || { strata_log_error "target is outside a Strata tier: $rel"; exit 1; }
status=$(strata_extract_scalar "$abs" status)
[ -n "$status" ] || status=$(strata_default_status "$strata" "$rel")

id=$(strata_extract_scalar "$abs" id)
[ -n "$id" ] || id=$(strata_make_id "$rel")

title=$(strata_extract_scalar "$abs" title)
if [ -z "$title" ]; then
    title=$(basename -- "$abs" .md | sed 's/-/ /g')
fi

description=$(strata_extract_scalar "$abs" description)
sources=$(strata_extract_array_block "$abs" sources || true)
tags=$(strata_extract_array_block "$abs" tags || true)
source_note=$(strata_extract_scalar "$abs" source_note)
last_edit_summary=$(strata_extract_scalar "$abs" last_edit_summary)
promoted_at=$(strata_extract_scalar "$abs" promoted_at)
version=$(strata_extract_scalar "$abs" version)
[ -n "$version" ] || version=1
created=$(strata_extract_scalar "$abs" created)
[ -n "$created" ] || created=$(date -u '+%Y-%m-%d')
modified=$(date -u '+%Y-%m-%d')

if { [ "$strata" = "2_knowledge" ] || [ "$strata" = "3_intelligence" ]; } && [ -z "$description" ]; then
    if [ "$json" = true ]; then
        printf '{"ok":false,"error":"description_required","path":'
        strata_json_string "$rel"
        printf '}\n'
    else
        strata_log_error "description is required for durable tier: $rel"
    fi
    exit 1
fi

tmp_root="${vault}/0_core/tmp"
mkdir -p "$tmp_root"
tmp=$(mktemp "${tmp_root}/normalize-XXXXXXXX")
trap 'rm -f "$tmp"' EXIT HUP INT TERM

{
    printf '%s\n' '---'
    printf 'id: "%s"\n' "$id"
    printf 'title: "%s"\n' "$title"
    printf 'description: "%s"\n' "$description"
    printf 'strata: "%s"\n' "$strata"
    printf 'status: "%s"\n' "$status"
    if [ -n "$tags" ]; then
        printf '%s\n' "$tags"
    else
        printf '%s\n' 'tags:'
    fi
    if [ "$strata" = "2_knowledge" ] || [ "$strata" = "3_intelligence" ]; then
        if [ -n "$sources" ]; then
            printf '%s\n' "$sources"
        else
            printf '%s\n' 'sources:'
        fi
        if [ -n "$source_note" ]; then
            printf 'source_note: "%s"\n' "$source_note"
        fi
    elif [ -n "$sources" ]; then
        printf '%s\n' "$sources"
    fi
    printf 'version: %s\n' "$version"
    if [ -n "$last_edit_summary" ]; then
        printf 'last_edit_summary: "%s"\n' "$last_edit_summary"
    fi
    printf 'created: "%s"\n' "$created"
    printf 'modified: "%s"\n' "$modified"
    if [ -n "$promoted_at" ]; then
        printf 'promoted_at: "%s"\n' "$promoted_at"
    fi
    printf '%s\n' '---'
    strata_extract_body "$abs"
} > "$tmp"

if [ "$check" = false ]; then
    mv "$tmp" "$abs"
    trap - EXIT HUP INT TERM
else
    rm -f "$tmp"
    trap - EXIT HUP INT TERM
fi

if [ "$json" = true ]; then
    printf '{"ok":true,"path":'
    strata_json_string "$rel"
    printf ',"strata":'
    strata_json_string "$strata"
    printf ',"status":'
    strata_json_string "$status"
    printf '}\n'
else
    if [ "$check" = true ]; then
        printf 'Normalized check passed: %s\n' "$rel"
    else
        printf 'Normalized: %s\n' "$rel"
    fi
fi
