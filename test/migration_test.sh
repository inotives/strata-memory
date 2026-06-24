#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
WORK=$(mktemp -d "${TMP_ROOT}/migration-test-XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
OLD="${WORK}/old-memory"
VAULT="${WORK}/vault"
STRATA_BIN="${VAULT}/0_core/bin/strata"

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

cargo build --release --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

mkdir -p \
    "$OLD/2_knowledges/Concepts" \
    "$OLD/2_knowledges/Researches/One" \
    "$OLD/2_knowledges/Researches/Two" \
    "$OLD/2_knowledges/Notes" \
    "$OLD/2_knowledges/News" \
    "$OLD/2_knowledges/Sources" \
    "$OLD/2_knowledges/Entities/Calendar/Financial Events" \
    "$OLD/2_knowledges/Entities/Companies/Solidus Labs" \
    "$OLD/2_knowledges/Entities/Stocks/AAPL/Daily" \
    "$OLD/2_knowledges/Entities/Work" \
    "$OLD/0_configs/rules" \
    "$OLD/1_drafts/Sessions" \
    "$OLD/3_intelligences/Skills/Coding/Review" \
    "$OLD/3_intelligences/Reports/Researches" \
    "$OLD/3_intelligences/Reports/Theses/AAPL/Bull"

cat > "$OLD/2_knowledges/Concepts/Alpha Note.md" <<EOF
---
title: "Alpha Note"
tags:
  - memory
---
# Alpha Note

See [[Daily Plan]] and ${OLD}/2_knowledges/Entities/Stocks/AAPL/Daily/Daily Plan.md.
Also see [[Duplicate]] and [[Missing Idea]].
EOF

cat > "$OLD/2_knowledges/Researches/One/Duplicate.md" <<'EOF'
# Duplicate One
EOF

cat > "$OLD/2_knowledges/Researches/Two/Duplicate.md" <<'EOF'
# Duplicate Two
EOF

cat > "$OLD/2_knowledges/Entities/Stocks/AAPL/Daily/Daily Plan.md" <<'EOF'
---
title: "Daily Plan"
tags:
  - research
---
# Daily Plan
EOF

cat > "$OLD/2_knowledges/Entities/Companies/Solidus Labs/Profile.md" <<'EOF'
# Solidus Labs

Company note without managed tags.
EOF

cat > "$OLD/2_knowledges/Entities/Calendar/Financial Events/2026-05-15.md" <<'EOF'
# Financial Event

Calendar capture without managed tags.
EOF

cat > "$OLD/2_knowledges/Entities/Work/Core Backbone Dependencies by Schema.md" <<'EOF'
# Core Backbone Dependencies by Schema

Work note without managed tags.
EOF

cat > "$OLD/2_knowledges/Sources/Raw Source.md" <<'EOF'
# Raw Source
EOF

cat > "$OLD/2_knowledges/Notes/Human Note.md" <<'EOF'
# Human Note

No frontmatter or tags, manually added.
EOF

cat > "$OLD/2_knowledges/News/Market Update.md" <<'EOF'
# Market Update

Loose human news capture without tags.
EOF

cat > "$OLD/1_drafts/Sessions/Skip Me.md" <<'EOF'
# Skip Me
EOF

cat > "$OLD/3_intelligences/Skills/Coding/Review/SKILL.md" <<'EOF'
# Review Skill
EOF

cat > "$OLD/3_intelligences/Reports/Researches/Market Close.html" <<'EOF'
<html><body><h1>Market Close</h1></body></html>
EOF

cat > "$OLD/3_intelligences/Reports/Theses/AAPL/Bull/2026-05-15.json" <<'EOF'
{"ticker":"AAPL","stance":"bull"}
EOF

cat > "$OLD/AGENTS.md" <<'EOF'
# Legacy Agents
EOF

cat > "$OLD/0_configs/rules/knowledge-management.md" <<'EOF'
---
status: durable
---
# Knowledge Management
EOF

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

before=$(snapshot_old)
out=$("${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section knowledge --json)
after=$(snapshot_old)
[ "$before" = "$after" ] || fail "old memory changed during migration"

case "$out" in
    *'"ok":true'*'"written_count":10'*'"skipped_count":1'*) ;;
    *) fail "unexpected knowledge migration output: $out" ;;
esac

assert_file "$VAULT/2_knowledge/concept/alpha-note.md"
assert_file "$VAULT/2_knowledge/note/human-note.md"
assert_file "$VAULT/2_knowledge/entity/company/solidus-labs/profile.md"
assert_file "$VAULT/2_knowledge/entity/stock/aapl/daily/daily-plan.md"
assert_file "$VAULT/2_knowledge/research/one/duplicate.md"
assert_file "$VAULT/2_knowledge/research/two/duplicate.md"
assert_file "$VAULT/2_knowledge/_unmapped/entity/calendar/financial-events/2026-05-15.md"
assert_file "$VAULT/2_knowledge/_unmapped/entity/work/core-backbone-dependencies-by-schema.md"
assert_file "$VAULT/2_knowledge/_unmapped/news/market-update.md"
assert_file "$VAULT/2_knowledge/_unmapped/sources/raw-source.md"
assert_missing "$VAULT/1_draft/session/skip-me.md"
assert_contains "$VAULT/2_knowledge/concept/alpha-note.md" "[Daily Plan]"
assert_contains "$VAULT/2_knowledge/entity/stock/aapl/daily/daily-plan.md" 'ticker: "AAPL"'
assert_contains "$VAULT/2_knowledge/entity/company/solidus-labs/profile.md" 'display_name: "Solidus Labs"'

report=$(find "$VAULT/3_intelligence/report/migration" -type f -name 'migration-knowledge-*.json' | sort | tail -1)
assert_file "$report"
assert_contains "$report" '"kind":"mapped"'
assert_contains "$report" '"kind":"unmapped"'
assert_contains "$report" '"kind":"skipped"'
assert_contains "$report" '"kind":"rewritten"'
assert_contains "$report" '"kind":"metadata"'
assert_contains "$report" '"metadata_count": 2'
assert_contains "$report" '"source_mode": "read-only"'
assert_contains "$report" 'ambiguous wikilink: Duplicate'
assert_contains "$report" 'unresolved wikilink: Missing Idea'

rerun=$("${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section knowledge --json)
case "$rerun" in
    *'"written_count":0'*'"existing_count":10'*) ;;
    *) fail "expected idempotent rerun, got: $rerun" ;;
esac

"${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section intelligence >/dev/null
assert_file "$VAULT/3_intelligence/skill/coding/review/skill.md"
assert_file "$VAULT/3_intelligence/report/research/market-close.html"
assert_file "$VAULT/3_intelligence/report/theses/aapl/bull/2026-05-15.json"
assert_contains "$VAULT/3_intelligence/report/research/market-close.html" '<h1>Market Close</h1>'
assert_contains "$VAULT/3_intelligence/report/theses/aapl/bull/2026-05-15.json" '"stance":"bull"'

REPORTS_VAULT="${WORK}/vault-reports"
"${ROOT}/install.sh" --vault "$REPORTS_VAULT" >/dev/null
"${REPORTS_VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$REPORTS_VAULT" --section reports >/dev/null
assert_file "$REPORTS_VAULT/3_intelligence/report/research/market-close.html"
assert_file "$REPORTS_VAULT/3_intelligence/report/theses/aapl/bull/2026-05-15.json"
assert_missing "$REPORTS_VAULT/3_intelligence/skill/coding/review/skill.md"

"${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section agents-md >/dev/null
assert_file "$VAULT/3_intelligence/agent/legacy-agents.md"

"${VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$VAULT" --section config >/dev/null
assert_file "$VAULT/2_knowledge/_unmapped/config/rules/knowledge-management.md"
assert_contains "$VAULT/2_knowledge/_unmapped/config/rules/knowledge-management.md" 'status: "verified"'

ALL_VAULT="${WORK}/vault-all"
"${ROOT}/install.sh" --vault "$ALL_VAULT" >/dev/null
all_out=$("${ALL_VAULT}/0_core/script/migration.sh" --from "$OLD" --to "$ALL_VAULT" --all --json)
case "$all_out" in
    *'"ok":true'*'"section":"all"'*) ;;
    *) fail "unexpected all migration output: $all_out" ;;
esac
assert_file "$ALL_VAULT/2_knowledge/concept/alpha-note.md"
assert_file "$ALL_VAULT/2_knowledge/_unmapped/config/rules/knowledge-management.md"
assert_file "$ALL_VAULT/3_intelligence/skill/coding/review/skill.md"
assert_file "$ALL_VAULT/3_intelligence/report/research/market-close.html"
assert_file "$ALL_VAULT/3_intelligence/agent/legacy-agents.md"

COLLIDE="${WORK}/old-collide"
COLLIDE_VAULT="${WORK}/vault-collide"
mkdir -p "$COLLIDE/2_knowledges/Concepts"
cat > "$COLLIDE/2_knowledges/Concepts/AAPL!.md" <<'EOF'
# AAPL!
EOF
cat > "$COLLIDE/2_knowledges/Concepts/AAPL@.md" <<'EOF'
# AAPL@
EOF
"${ROOT}/install.sh" --vault "$COLLIDE_VAULT" >/dev/null
if "${COLLIDE_VAULT}/0_core/script/migration.sh" --from "$COLLIDE" --to "$COLLIDE_VAULT" --section knowledge >/dev/null 2>&1; then
    fail "expected collision to block migration"
fi

"$STRATA_BIN" search --vault "$VAULT" --query "Alpha" --limit 1 >/dev/null

printf 'ok - migration passed\n'
