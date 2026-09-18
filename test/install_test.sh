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

assert_single_line() {
    [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = 1 ] || fail "expected one line"
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

assert_dir "${VAULT}/0_core/script/lib"
assert_dir "${VAULT}/0_core/bin"
assert_dir "${VAULT}/0_core/template_override"
assert_dir "${VAULT}/0_resource/images"
assert_dir "${VAULT}/0_resource/scripts"
assert_dir "${VAULT}/0_resource/data"
assert_dir "${VAULT}/0_resource/other"
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
printf '%s\n' 'Ignored resource fixture.' > "${VAULT}/0_resource/other/ignored-resource.md"
"${VAULT}/0_core/bin/strata" --help >/dev/null
"${VAULT}/0_core/bin/strata" doctor --vault "$VAULT" >/dev/null
"${VAULT}/0_core/bin/strata" search --query "example" --vault "$VAULT" >/dev/null

printf '%s\n' '# user configuration is preserved' >> "${VAULT}/0_core/config/configs.yaml"
mkdir -p "${VAULT}/2_knowledge/concept"
cat > "${VAULT}/2_knowledge/concept/user.md" <<'MARKDOWN'
---
title: User Content
description: Content preserved across installation.
status: verified
---

# User Content
MARKDOWN

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

assert_contains "${VAULT}/0_core/config/configs.yaml" "user configuration is preserved"
assert_contains "${VAULT}/2_knowledge/concept/user.md" "User Content"
assert_contains "${VAULT}/0_core/manifest.json" '"managed_root": "0_core"'
assert_contains "${VAULT}/0_core/manifest.json" '"path":"0_core/bin/strata"'
assert_contains "${VAULT}/0_core/manifest.json" '"path":"0_core/script/migration.sh"'
"${VAULT}/0_core/bin/strata" doctor --vault "$VAULT" >/dev/null
"${VAULT}/0_core/bin/strata" search --query "User Content" --vault "$VAULT" | grep -F 'User Content' >/dev/null

JSON_VAULT=$(mktemp -d "${TMP_ROOT}/install-json-test-XXXXXXXX")
JSON_OUTPUT=$("${ROOT}/install.sh" --vault "$JSON_VAULT" --json)
rm -rf "$JSON_VAULT"
assert_single_line "$JSON_OUTPUT"
case "$JSON_OUTPUT" in
    '{"ok":true,"vault":'*',"manifest":'*'}') ;;
    *) fail "expected installer JSON output" ;;
esac

printf 'ok - install fixture passed\n'
