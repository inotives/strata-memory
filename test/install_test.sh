#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/install-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_file() {
    [ -f "$1" ] || fail "expected file: $1"
}

assert_dir() {
    [ -d "$1" ] || fail "expected directory: $1"
}

assert_contains() {
    local file=$1
    local needle=$2
    grep -F "$needle" "$file" >/dev/null 2>&1 || fail "expected '$needle' in $file"
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

assert_dir "${VAULT}/0_core/script/lib"
assert_dir "${VAULT}/0_core/bin"
assert_dir "${VAULT}/0_core/template_override"
assert_dir "${VAULT}/1_draft/research"
assert_dir "${VAULT}/2_knowledge/entity"
assert_dir "${VAULT}/3_intelligence/workflow"
assert_file "${VAULT}/0_core/bin/strata"
assert_file "${VAULT}/0_core/script/migration.sh"
assert_file "${VAULT}/0_core/script/lib/paths.sh"
assert_file "${VAULT}/0_core/config/configs.yaml"
assert_file "${VAULT}/0_core/db/sqlite/schema.sql"
assert_file "${VAULT}/0_core/db/sqlite/migrations/001_init.sql"
assert_file "${VAULT}/0_core/db/turso/schema.sql"
assert_file "${VAULT}/0_core/db/turso/migrations/001_init.sql"
assert_file "${VAULT}/0_core/doc/commands.md"
assert_file "${VAULT}/0_core/manifest.json"
assert_file "${VAULT}/.gitignore"
assert_file "${VAULT}/AGENTS.md"
"${VAULT}/0_core/bin/strata" --help >/dev/null

printf '%s\n' 'user_config: true' > "${VAULT}/0_core/config/configs.yaml"
mkdir -p "${VAULT}/2_knowledge/concept"
printf '%s\n' 'user content' > "${VAULT}/2_knowledge/concept/user.md"

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

assert_contains "${VAULT}/0_core/config/configs.yaml" "user_config: true"
assert_contains "${VAULT}/2_knowledge/concept/user.md" "user content"
assert_contains "${VAULT}/0_core/manifest.json" '"managed_root": "0_core"'
assert_contains "${VAULT}/0_core/manifest.json" '"path":"0_core/bin/strata"'
assert_contains "${VAULT}/0_core/manifest.json" '"path":"0_core/script/migration.sh"'

printf 'ok - install fixture passed\n'
