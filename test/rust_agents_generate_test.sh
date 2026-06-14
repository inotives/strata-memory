#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-agents-generate-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local needle=$2
    grep -F -- "$needle" "$file" >/dev/null 2>&1 || fail "expected '$needle' in $file"
}

assert_count() {
    local file=$1
    local needle=$2
    local expected=$3
    local actual
    actual=$(grep -F -- "$needle" "$file" | wc -l | awk '{print $1}')
    [ "$actual" = "$expected" ] || fail "expected $expected occurrences of '$needle', got $actual"
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

cat > "${VAULT}/AGENTS.md" <<'EOF'
# Custom Vault Prompt

<!-- STRATA_GENERATED_START -->
old generated content
<!-- STRATA_GENERATED_END -->

<!-- STRATA_MANUAL_START -->
keep this manual instruction
<!-- STRATA_MANUAL_END -->
EOF

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

"$STRATA_BIN" agents-generate --vault "$VAULT" >/dev/null
assert_contains "${VAULT}/AGENTS.md" '# Strata-Memory'
assert_contains "${VAULT}/AGENTS.md" '0_core/template/draft/research-draft.md'
assert_contains "${VAULT}/AGENTS.md" 'Profile: `coder`'
assert_contains "${VAULT}/AGENTS.md" '- `entity/project/*`'
assert_contains "${VAULT}/AGENTS.md" '- `entity/tool/*`'
assert_contains "${VAULT}/AGENTS.md" 'run `strata refresh` once per session'
assert_contains "${VAULT}/AGENTS.md" '| `strata:refresh` | Refresh the derived SQLite index with a full scan. |'
assert_contains "${VAULT}/AGENTS.md" '| `strata:link-review` | Review invalid or broken vault links. |'
assert_contains "${VAULT}/AGENTS.md" 'keep this manual instruction'
assert_count "${VAULT}/AGENTS.md" '<!-- STRATA_GENERATED_START -->' 1
assert_count "${VAULT}/AGENTS.md" '<!-- STRATA_MANUAL_START -->' 1

sed -i 's/profile: "coder"/profile: "trader"/' "${VAULT}/0_core/config/configs.yaml"
json=$("$STRATA_BIN" agents-generate --vault "$VAULT" --json)
case "$json" in
    *'"profile":"trader"'*) ;;
    *) fail "expected trader json: $json" ;;
esac
assert_contains "${VAULT}/AGENTS.md" 'Profile: `trader`'
assert_contains "${VAULT}/AGENTS.md" '- `entity/stock/*`'
assert_contains "${VAULT}/AGENTS.md" 'keep this manual instruction'

printf 'ok - rust agents generate passed\n'
