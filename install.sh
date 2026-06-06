#!/usr/bin/env bash
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="${REPO_ROOT}/src"
VAULT=${STRATA_VAULT:-"${HOME}/.strata-memory"}
CORE="${VAULT}/0_core"

usage() {
    cat <<'USAGE'
Usage: install.sh [--vault PATH] [--json]

Install managed Strata-Memory engine files into a private vault.
Existing user config at 0_core/config/configs.yaml is preserved.
USAGE
}

json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vault)
            VAULT=$2
            CORE="${VAULT}/0_core"
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

case "$VAULT" in
    /*) ;;
    *) VAULT=$(mkdir -p "$VAULT" && CDPATH= cd -- "$VAULT" && pwd) ;;
esac
CORE="${VAULT}/0_core"

copy_tree() {
    local src=$1
    local dst=$2
    [ -d "$src" ] || return 0
    mkdir -p "$dst"
    (
        cd "$src"
        find . -type d -exec mkdir -p "$dst/{}" \;
        find . -type f | while IFS= read -r rel; do
            mkdir -p "$(dirname "$dst/$rel")"
            cp "$rel" "$dst/$rel"
        done
    )
}

write_manifest() {
    local manifest="${CORE}/manifest.json"
    local now
    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    {
        printf '{\n'
        printf '  "generated_at": "%s",\n' "$now"
        printf '  "managed_root": "0_core",\n'
        printf '  "files": [\n'
        (
            cd "$CORE"
            find db doc script template -type f 2>/dev/null | sort | while IFS= read -r file; do
                cksum_out=$(cksum "$file")
                checksum=${cksum_out%% *}
                size_rest=${cksum_out#* }
                size=${size_rest%% *}
                printf '    {"path":"0_core/%s","cksum":"%s","size":%s},\n' "$file" "$checksum" "$size"
            done | sed '$ s/,$//'
        )
        printf '  ]\n'
        printf '}\n'
    } > "$manifest"
}

mkdir -p "$CORE"

"${SRC_DIR}/script/init.sh" --vault "$VAULT" >/dev/null

copy_tree "${SRC_DIR}/script" "${CORE}/script"
copy_tree "${SRC_DIR}/db" "${CORE}/db"
copy_tree "${SRC_DIR}/doc" "${CORE}/doc"
copy_tree "${SRC_DIR}/template" "${CORE}/template"

if [ ! -f "${CORE}/config/configs.yaml" ]; then
    cp "${SRC_DIR}/template/config/configs.yaml" "${CORE}/config/configs.yaml"
fi

if [ ! -f "${VAULT}/.gitignore" ]; then
    cp "${SRC_DIR}/template/vault/gitignore" "${VAULT}/.gitignore"
fi

if [ ! -f "${VAULT}/AGENTS.md" ]; then
    cp "${SRC_DIR}/template/agents/base.md" "${VAULT}/AGENTS.md"
fi

find "${CORE}/script" -type f -name '*.sh' -exec chmod +x {} \;
write_manifest

if [ "$json" = true ]; then
    printf '{"ok":true,"vault":"%s","manifest":"%s"}\n' "$VAULT" "${CORE}/manifest.json"
else
    printf 'Installed Strata-Memory into %s\n' "$VAULT"
    printf 'Managed manifest: %s\n' "${CORE}/manifest.json"
fi
