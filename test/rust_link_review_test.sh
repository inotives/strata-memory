#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-link-review-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack=$1
    local needle=$2
    local label=$3
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "$label: expected '$needle' in '$haystack'" ;;
    esac
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

mkdir -p "${VAULT}/1_draft/note" "${VAULT}/2_knowledge/research"

cat > "${VAULT}/2_knowledge/research/good-target.md" <<'EOF'
---
title: "Good Target"
description: "Target."
tags:
  - research
sources:
  - "../../1_draft/_archived/research/good-target.md"
---
# Target
EOF

cat > "${VAULT}/1_draft/note/draft-links.md" <<'EOF'
---
title: "Draft Links"
description: ""
tags:
  - research
---
# Draft

[missing](missing.md)
EOF

cat > "${VAULT}/2_knowledge/research/broken-links.md" <<'EOF'
---
title: "Broken Links"
description: "Durable broken links should fail."
tags:
  - research
sources:
  - "../../1_draft/_archived/research/broken-links.md"
---
# Broken

[good](good-target.md)
[missing](missing.md)
[[wikilink]]
EOF

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

if links=$("$STRATA_BIN" link-review --vault "$VAULT" --json 2>/dev/null); then
    fail "durable broken links should fail"
fi
assert_contains "$links" '"ok":false' "json not ok"
assert_contains "$links" '"reason":"broken_local_link"' "broken local"
assert_contains "$links" '"reason":"wikilink_not_allowed"' "wikilink"
assert_contains "$links" '"severity":"warn"' "draft warning"
assert_contains "$links" '"severity":"error"' "durable error"

printf 'ok - rust link review passed\n'
