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
Usage: promote.sh --source FILE --to 2_knowledge|3_intelligence [--new-slug SLUG] [--vault PATH] [--json]

Promote a draft into a durable tier, archive the original draft, and re-index both files.
USAGE
}

source=
to=
new_slug=
json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source)
            source=$2
            shift 2
            ;;
        --to)
            to=$2
            shift 2
            ;;
        --new-slug)
            new_slug=$2
            shift 2
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

[ -n "$source" ] || { usage >&2; exit 2; }
[ -n "$to" ] || { usage >&2; exit 2; }
case "$to" in
    2_knowledge|3_intelligence) ;;
    *) strata_log_error "--to must be 2_knowledge or 3_intelligence"; exit 2 ;;
esac

vault=$(strata_vault)
case "$source" in
    /*) source_abs=$source ;;
    *) source_abs=$(CDPATH= cd -- "$(dirname -- "$source")" && pwd)/$(basename -- "$source") ;;
esac

[ -f "$source_abs" ] || { strata_log_error "source not found: $source"; exit 1; }
source_rel=$(strata_rel_path "$source_abs" "$vault")
case "$source_rel" in
    1_draft/*) ;;
    *) strata_log_error "source must be under 1_draft: $source_rel"; exit 1 ;;
esac

description=$(strata_extract_scalar "$source_abs" description)
if [ -z "$description" ]; then
    strata_log_error "description is required before promotion: $source_rel"
    exit 1
fi

status=$(strata_extract_scalar "$source_abs" status)
case "$status" in
    ""|pending) ;;
    *) strata_log_error "only pending drafts can be promoted: $source_rel"; exit 1 ;;
esac

draft_subpath=${source_rel#1_draft/}
case "$draft_subpath" in
    _archived/*) strata_log_error "archived drafts cannot be promoted: $source_rel"; exit 1 ;;
esac
draft_dir=$(dirname "$draft_subpath")
draft_base=$(basename "$draft_subpath")

if [ -n "$new_slug" ]; then
    case "$new_slug" in
        *[!a-z0-9._-]*|"" ) strata_log_error "--new-slug must use lowercase letters, numbers, dot, underscore, or dash"; exit 2 ;;
    esac
    case "$new_slug" in
        *.md) draft_base=$new_slug ;;
        *) draft_base="${new_slug}.md" ;;
    esac
fi

target_rel="${to}/${draft_dir}/${draft_base}"
archive_rel="1_draft/_archived/${draft_subpath}"
target_abs="${vault}/${target_rel}"
archive_abs="${vault}/${archive_rel}"

if [ -e "$target_abs" ]; then
    strata_log_error "target exists; use --new-slug: $target_rel"
    exit 1
fi
if [ -e "$archive_abs" ]; then
    strata_log_error "archive target exists: $archive_rel"
    exit 1
fi

op_dir=$(mktemp -d "${vault}/0_core/tmp/promote-XXXXXXXX")
promoted_tmp="${op_dir}/promoted.md"
archived_tmp="${op_dir}/archived.md"
log_tmp="${op_dir}/operation.log"

fail_with_tmp() {
    strata_log_error "$1"
    strata_log_error "left temp files at: $op_dir"
    exit 1
}

build_candidate() {
    local src=$1
    local dst=$2
    local strata=$3
    local status_value=$4
    local rel_for_id=$5
    local archived_from=$6
    local now
    local id
    local title
    local tags
    local sources
    local source_note
    local version
    local created
    local last_edit_summary

    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    id=$(strata_extract_scalar "$src" id)
    [ -n "$id" ] || id=$(strata_make_id "$rel_for_id")
    if [ -n "$archived_from" ]; then
        id="${id}_archived"
    fi
    title=$(strata_extract_scalar "$src" title)
    [ -n "$title" ] || title=$(basename -- "$rel_for_id" .md | sed 's/-/ /g')
    tags=$(strata_extract_array_block "$src" tags || true)
    sources=$(strata_extract_array_block "$src" sources || true)
    source_note=$(strata_extract_scalar "$src" source_note)
    version=$(strata_extract_scalar "$src" version)
    [ -n "$version" ] || version=1
    created=$(strata_extract_scalar "$src" created)
    [ -n "$created" ] || created=$(date -u '+%Y-%m-%d')
    last_edit_summary=$(strata_extract_scalar "$src" last_edit_summary)

    {
        printf '%s\n' '---'
        printf 'id: "%s"\n' "$id"
        printf 'title: "%s"\n' "$title"
        printf 'description: "%s"\n' "$description"
        printf 'strata: "%s"\n' "$strata"
        printf 'status: "%s"\n' "$status_value"
        if [ -n "$tags" ]; then
            printf '%s\n' "$tags"
        else
            printf '%s\n' 'tags:'
        fi
        if [ "$strata" = "2_knowledge" ] || [ "$strata" = "3_intelligence" ]; then
            printf '%s\n' 'sources:'
            printf '  - "%s"\n' "$archive_rel"
            if [ -n "$source_note" ]; then
                printf 'source_note: "%s"\n' "$source_note"
            else
                printf 'source_note: "Promoted from archived draft."\n'
            fi
            printf 'promoted_at: "%s"\n' "$now"
        elif [ -n "$sources" ]; then
            printf '%s\n' "$sources"
        fi
        printf 'version: %s\n' "$version"
        if [ -n "$last_edit_summary" ]; then
            printf 'last_edit_summary: "%s"\n' "$last_edit_summary"
        fi
        printf 'created: "%s"\n' "$created"
        printf 'modified: "%s"\n' "$(date -u '+%Y-%m-%d')"
        if [ -n "$archived_from" ]; then
            printf 'archived_at: "%s"\n' "$now"
            printf 'archived_reason: "Promoted to %s."\n' "$target_rel"
            printf 'archived_from: "%s"\n' "$archived_from"
        fi
        printf '%s\n' '---'
        strata_extract_body "$src"
    } > "$dst"
}

build_candidate "$source_abs" "$promoted_tmp" "$to" "verified" "$target_rel" ""
build_candidate "$source_abs" "$archived_tmp" "1_draft" "archived" "$archive_rel" "$source_rel"

"${SCRIPT_DIR}/normalize.sh" --vault "$vault" --target "$promoted_tmp" --check >/dev/null || fail_with_tmp "promoted candidate failed normalization"
"${SCRIPT_DIR}/normalize.sh" --vault "$vault" --target "$archived_tmp" --check >/dev/null || fail_with_tmp "archived candidate failed normalization"

mkdir -p "$(dirname "$target_abs")" "$(dirname "$archive_abs")" "${vault}/3_intelligence/report/operation"

cp "$promoted_tmp" "$target_abs" || fail_with_tmp "failed to write target"
cp "$archived_tmp" "$archive_abs" || fail_with_tmp "failed to write archive"

if [ ! -f "$target_abs" ] || [ ! -f "$archive_abs" ]; then
    fail_with_tmp "final files were not created"
fi

rm -f "$source_abs" || fail_with_tmp "failed to remove original draft"

"${SCRIPT_DIR}/index.sh" --vault "$vault" --target "$target_abs" >/dev/null || fail_with_tmp "failed to index target"
"${SCRIPT_DIR}/index.sh" --vault "$vault" --target "$archive_abs" >/dev/null || fail_with_tmp "failed to index archive"

operation_log="${vault}/3_intelligence/report/operation/promote-$(date -u '+%Y%m%d-%H%M%S').json"
{
    printf '{"ok":true,"source":'
    strata_json_string "$source_rel"
    printf ',"target":'
    strata_json_string "$target_rel"
    printf ',"archive":'
    strata_json_string "$archive_rel"
    printf '}\n'
} > "$log_tmp"
mv "$log_tmp" "$operation_log"

rm -rf "$op_dir"

if [ "$json" = true ]; then
    printf '{"ok":true,"target":'
    strata_json_string "$target_rel"
    printf ',"archive":'
    strata_json_string "$archive_rel"
    printf ',"log":'
    strata_json_string "$(strata_rel_path "$operation_log" "$vault")"
    printf '}\n'
else
    printf 'Promoted: %s\n' "$target_rel"
    printf 'Archived: %s\n' "$archive_rel"
fi
