#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
WORK=$(mktemp -d "${TMP_ROOT}/migration-test-XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
OLD="${WORK}/old-memory"
VAULT="${WORK}/vault"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_file() {
    [ -f "$1" ] || fail "expected file: $1"
}

assert_missing() {
    [ ! -e "$1" ] || fail "expected missing: $1"
}

assert_contains() {
    local file=$1
    local needle=$2
    grep -F -- "$needle" "$file" >/dev/null 2>&1 || fail "expected '$needle' in $file"
}

snapshot_old() {
    (cd "$OLD" && find . -type f -print | sort | while IFS= read -r file; do cksum "$file"; done)
}

mkdir -p \
    "$OLD/2_knowledges/Concepts" \
    "$OLD/2_knowledges/Sources" \
    "$OLD/2_knowledges/Entities/Stocks/AAPL/Daily" \
    "$OLD/1_drafts/Sessions" \
    "$OLD/3_intelligences/Skills/Coding/Review"

cat > "$OLD/2_knowledges/Concepts/Alpha Note.md" <<EOF
---
title: "Alpha Note"
tags:
  - memory
---
# Alpha Note

See [[Daily Plan]] and ${OLD}/2_knowledges/Entities/Stocks/AAPL/Daily/Daily Plan.md.
EOF

cat > "$OLD/2_knowledges/Entities/Stocks/AAPL/Daily/Daily Plan.md" <<'EOF'
---
title: "Daily Plan"
tags:
  - research
---
# Daily Plan
EOF

cat > "$OLD/2_knowledges/Sources/Raw Source.md" <<'EOF'
# Raw Source
EOF

cat > "$OLD/1_drafts/Sessions/Skip Me.md" <<'EOF'
# Skip Me
EOF

cat > "$OLD/3_intelligences/Skills/Coding/Review/SKILL.md" <<'EOF'
# Review Skill
EOF

cat > "$OLD/AGENTS.md" <<'EOF'
# Legacy Agents
EOF

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

before=$(snapshot_old)
out=$("${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section knowledge --json)
after=$(snapshot_old)
[ "$before" = "$after" ] || fail "old memory changed during migration"

case "$out" in
    *'"ok":true'*'"written_count":3'*'"skipped_count":1'*) ;;
    *) fail "unexpected knowledge migration output: $out" ;;
esac

assert_file "$VAULT/2_knowledge/concept/alpha-note.md"
assert_file "$VAULT/2_knowledge/entity/stock/aapl/daily/daily-plan.md"
assert_file "$VAULT/2_knowledge/_unmapped/sources/raw-source.md"
assert_missing "$VAULT/1_draft/session/skip-me.md"
assert_contains "$VAULT/2_knowledge/concept/alpha-note.md" "[Daily Plan]"

report=$(find "$VAULT/3_intelligence/report/migration" -type f -name 'migration-knowledge-*.json' | sort | tail -1)
assert_file "$report"
assert_contains "$report" '"kind":"mapped"'
assert_contains "$report" '"kind":"unmapped"'
assert_contains "$report" '"kind":"skipped"'
assert_contains "$report" '"kind":"rewritten"'

rerun=$("${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section knowledge --json)
case "$rerun" in
    *'"written_count":0'*'"existing_count":3'*) ;;
    *) fail "expected idempotent rerun, got: $rerun" ;;
esac

"${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section intelligence >/dev/null
assert_file "$VAULT/3_intelligence/skill/coding/review/skill.md"

"${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section agents-md >/dev/null
assert_file "$VAULT/3_intelligence/agent/legacy-agents.md"

COLLIDE="${WORK}/old-collide"
COLLIDE_VAULT="${WORK}/vault-collide"
mkdir -p "$COLLIDE/2_knowledges/Concepts"
cat > "$COLLIDE/2_knowledges/Concepts/AAPL.md" <<'EOF'
# AAPL
EOF
cat > "$COLLIDE/2_knowledges/Concepts/aapl.md" <<'EOF'
# aapl
EOF
"${ROOT}/install.sh" --vault "$COLLIDE_VAULT" >/dev/null
if "${COLLIDE_VAULT}/0_core/script/migration.sh" --from "$COLLIDE" --to "$COLLIDE_VAULT" --section knowledge >/dev/null 2>&1; then
    fail "expected collision to block migration"
fi

"${VAULT}/0_core/script/search.sh" --vault "$VAULT" --query "Alpha" --limit 1 >/dev/null

printf 'ok - migration passed\n'
