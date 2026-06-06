#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/review-test-XXXXXXXX")
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

mkdir -p \
    "${VAULT}/2_knowledge/concept" \
    "${VAULT}/2_knowledge/entity/stock/aapl/daily" \
    "${VAULT}/2_knowledge/entity/unknown/foo" \
    "${VAULT}/1_draft/note" \
    "${VAULT}/2_knowledge/research"

cat > "${VAULT}/2_knowledge/concept/tagged.md" <<'EOF'
---
title: "Tagged"
description: "Used for tag review."
tags:
  - Research
  - unknown-tag
sources:
  - "../../1_draft/_archived/research/tagged.md"
---
# Tagged

Body.
EOF

cat > "${VAULT}/2_knowledge/entity/stock/aapl/daily/2026-06-06.md" <<'EOF'
---
title: "AAPL Daily"
description: "Registered recursive room."
tags:
  - research
sources:
  - "../../../../1_draft/_archived/research/aapl.md"
---
# AAPL

Body.
EOF

cat > "${VAULT}/2_knowledge/entity/unknown/foo/page.md" <<'EOF'
---
title: "Unknown Room"
description: "Unregistered room."
tags:
  - research
sources:
  - "../../../../1_draft/_archived/research/unknown.md"
---
# Unknown

Body.
EOF

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

tags=$("${VAULT}/0_core/script/tag-review.sh" --vault "$VAULT" --json)
assert_contains "$tags" '"tag":"Research"' "tag case review"
assert_contains "$tags" '"similar":"research"' "tag similar"
assert_contains "$tags" '"tag":"unknown-tag"' "tag unknown"

rooms=$("${VAULT}/0_core/script/room-review.sh" --vault "$VAULT" --json)
assert_contains "$rooms" '"room":"2_knowledge/entity/unknown/foo"' "room unknown"
case "$rooms" in
    *"2_knowledge/entity/stock/aapl/daily"*) fail "registered recursive stock room should not be reported" ;;
esac

if links=$("${VAULT}/0_core/script/link-review.sh" --vault "$VAULT" --json 2>/dev/null); then
    fail "durable broken links should fail"
fi
assert_contains "$links" '"reason":"broken_local_link"' "broken local"
assert_contains "$links" '"reason":"wikilink_not_allowed"' "wikilink"
assert_contains "$links" '"severity":"warn"' "draft warning"
assert_contains "$links" '"severity":"error"' "durable error"

printf 'ok - reviews passed\n'
