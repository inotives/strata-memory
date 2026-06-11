#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-normalize-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local needle=$2
    grep -F "$needle" "$file" >/dev/null 2>&1 || fail "expected '$needle' in $file"
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null
STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

draft="${VAULT}/1_draft/note/no-frontmatter.md"
printf '# No Frontmatter\n\nBody text.\n' > "$draft"
"$STRATA_BIN" normalize --vault "$VAULT" --target "$draft" >/dev/null
assert_contains "$draft" 'strata: "1_draft"'
assert_contains "$draft" 'status: "pending"'
assert_contains "$draft" 'description: ""'
assert_contains "$draft" '# No Frontmatter'

partial="${VAULT}/1_draft/research/partial.md"
cat > "$partial" <<'EOF'
---
title: "Partial Draft"
tags:
  - research
---
Draft body.
EOF
"$STRATA_BIN" normalize --vault "$VAULT" --target "$partial" >/dev/null
assert_contains "$partial" 'title: "Partial Draft"'
assert_contains "$partial" '  - research'
assert_contains "$partial" 'Draft body.'

before=$(cksum "$partial")
"$STRATA_BIN" normalize --vault "$VAULT" --target "$partial" --check >/dev/null
after=$(cksum "$partial")
[ "$before" = "$after" ] || fail "expected --check not to modify target"

durable="${VAULT}/2_knowledge/research/quoted-time.md"
cat > "$durable" <<'EOF'
---
title: "Quoted Time"
description: "Timestamp parsing should split on the first colon only."
status: "verified"
sources:
  - "../../1_draft/_archived/research/quoted-time.md"
promoted_at: "2026-06-06T15:32:04Z"
---
Durable body.
EOF
"$STRATA_BIN" normalize --vault "$VAULT" --target "$durable" >/dev/null
assert_contains "$durable" 'promoted_at: "2026-06-06T15:32:04Z"'
assert_contains "$durable" 'strata: "2_knowledge"'
assert_contains "$durable" 'sources:'

missing_description="${VAULT}/2_knowledge/note/missing-description.md"
cat > "$missing_description" <<'EOF'
---
title: "Missing Description"
---
Body.
EOF
if "$STRATA_BIN" normalize --vault "$VAULT" --target "$missing_description" >/dev/null 2>&1; then
    fail "expected durable missing description to fail"
fi

json=$("$STRATA_BIN" normalize --vault "$VAULT" --target "$draft" --json)
case "$json" in
    *'"ok":true'*'"path":"1_draft/note/no-frontmatter.md"'*) ;;
    *) fail "expected normalize json success, got: $json" ;;
esac

printf 'ok - rust normalize passed\n'
