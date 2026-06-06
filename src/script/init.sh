#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

strata_usage() {
    cat <<'USAGE'
Usage: init.sh [--vault PATH] [--json]

Create the base Strata-Memory vault folders and check bootstrap dependencies.
USAGE
}

json=false
vault=${STRATA_VAULT:-"${HOME}/.strata-memory"}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vault)
            vault=$2
            shift 2
            ;;
        --json)
            json=true
            shift
            ;;
        --help|-h)
            strata_usage
            exit 0
            ;;
        *)
            printf '%s\n' "Unknown argument: $1" >&2
            strata_usage >&2
            exit 2
            ;;
    esac
done

strata_check_bootstrap_dependencies

mkdir -p \
    "${vault}/0_core/config" \
    "${vault}/0_core/cache" \
    "${vault}/0_core/db/migrations" \
    "${vault}/0_core/doc" \
    "${vault}/0_core/script/lib" \
    "${vault}/0_core/template" \
    "${vault}/0_core/template_override" \
    "${vault}/0_core/test/tmp" \
    "${vault}/0_core/tmp" \
    "${vault}/1_draft/research" \
    "${vault}/1_draft/note" \
    "${vault}/1_draft/skill" \
    "${vault}/1_draft/agent" \
    "${vault}/1_draft/workflow" \
    "${vault}/1_draft/session" \
    "${vault}/1_draft/_archived" \
    "${vault}/2_knowledge/concept" \
    "${vault}/2_knowledge/entity" \
    "${vault}/2_knowledge/research" \
    "${vault}/2_knowledge/note" \
    "${vault}/2_knowledge/preference" \
    "${vault}/2_knowledge/_archived" \
    "${vault}/3_intelligence/skill" \
    "${vault}/3_intelligence/agent" \
    "${vault}/3_intelligence/workflow" \
    "${vault}/3_intelligence/report" \
    "${vault}/3_intelligence/_archived"

if [ "$json" = true ]; then
    printf '{"ok":true,"vault":"%s"}\n' "$vault"
else
    printf 'Initialized Strata-Memory vault: %s\n' "$vault"
fi
