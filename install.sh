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

check_runtime_dependencies() {
    local dependency
    local missing=()

    for dependency in bash sqlite3 awk sed find sort mktemp cksum date; do
        command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
    done

    [ "${#missing[@]}" -eq 0 ] && return 0

    printf 'Missing runtime prerequisites: %s\n' "${missing[*]}" >&2
    case "$(uname -s)" in
        Darwin)
            printf '%s\n' 'Install the missing tools with Homebrew, then rerun install.sh.' >&2
            ;;
        Linux)
            printf '%s\n' 'On Debian/Ubuntu: sudo apt install sqlite3 bash gawk sed findutils coreutils' >&2
            ;;
    esac
    return 1
}

create_vault_dirs() {
    for rel in \
        "0_resource/images" \
        "0_resource/scripts" \
        "0_resource/data" \
        "0_resource/other" \
        "0_core/config" \
        "0_core/cache" \
        "0_core/db/sqlite/migrations" \
        "0_core/db/turso/migrations" \
        "0_core/doc" \
        "0_core/script/lib" \
        "0_core/template" \
        "0_core/template_override" \
        "0_core/test/tmp" \
        "0_core/tmp" \
        "1_draft/research" \
        "1_draft/note" \
        "1_draft/skill" \
        "1_draft/agent" \
        "1_draft/workflow" \
        "1_draft/session" \
        "2_knowledge/concept" \
        "2_knowledge/entity" \
        "2_knowledge/research" \
        "2_knowledge/note" \
        "2_knowledge/preference" \
        "3_intelligence/skill" \
        "3_intelligence/agent" \
        "3_intelligence/workflow" \
        "3_intelligence/report"
    do
        mkdir -p "${VAULT}/${rel}"
    done
}

build_strata() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)

    case "${os}/${arch}" in
        Linux/*|Darwin/arm64) ;;
        Darwin/*)
            printf '%s\n' "Unsupported platform: ${os}/${arch}. macOS requires Apple Silicon (arm64)." >&2
            exit 1
            ;;
        *)
            printf '%s\n' "Unsupported platform: ${os}/${arch}. Supported platforms are Linux and Apple Silicon macOS." >&2
            exit 1
            ;;
    esac

    if ! command -v cargo >/dev/null 2>&1; then
        printf '%s\n' "Missing prerequisite: cargo. Install Rust and Cargo, then rerun install.sh." >&2
        exit 1
    fi

    local cargo_args=(build --release --manifest-path "${SRC_DIR}/rust/strata/Cargo.toml")
    if [ "${STRATA_CARGO_OFFLINE:-0}" = 1 ]; then
        cargo_args+=(--offline)
    fi
    cargo "${cargo_args[@]}"
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
            find bin db doc script template -type f 2>/dev/null | sort | while IFS= read -r file; do
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

run_bootstrap() {
    local stage output line

    for stage in db-migrate refresh doctor; do
        if [ "$json" = true ]; then
            output=$(mktemp)
            if ! "${CORE}/bin/strata" "$stage" --vault "$VAULT" --json >"$output"; then
                while IFS= read -r line; do
                    printf '%s\n' "$line" >&2
                done < "$output"
                rm -f "$output"
                printf 'Installation bootstrap failed during %s\n' "$stage" >&2
                return 1
            fi
            rm -f "$output"
        else
            printf 'Bootstrapping: %s\n' "$stage"
            if ! "${CORE}/bin/strata" "$stage" --vault "$VAULT"; then
                printf 'Installation bootstrap failed during %s\n' "$stage" >&2
                return 1
            fi
        fi
    done
}

mkdir -p "$CORE"
check_runtime_dependencies
create_vault_dirs
build_strata

copy_tree "${SRC_DIR}/script" "${CORE}/script"
copy_tree "${SRC_DIR}/db" "${CORE}/db"
copy_tree "${SRC_DIR}/doc" "${CORE}/doc"
copy_tree "${SRC_DIR}/template" "${CORE}/template"

mkdir -p "${CORE}/bin"
cp "${SRC_DIR}/rust/strata/target/release/strata" "${CORE}/bin/strata"

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
[ ! -f "${CORE}/bin/strata" ] || chmod +x "${CORE}/bin/strata"
installed_version=$("${CORE}/bin/strata" version)
installed_version=${installed_version#strata }
write_manifest
run_bootstrap

if [ "$json" = true ]; then
    printf '{"ok":true,"vault":"%s","manifest":"%s","version":"%s"}\n' "$VAULT" "${CORE}/manifest.json" "$installed_version"
else
    printf 'Installed Strata-Memory into %s\n' "$VAULT"
    printf 'Installed version: %s\n' "$installed_version"
    printf 'Managed manifest: %s\n' "${CORE}/manifest.json"
fi
