#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-promote-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

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
    grep -F "$needle" "$file" >/dev/null 2>&1 || fail "expected '$needle' in $file"
}

assert_eq() {
    local actual=$1
    local expected=$2
    local label=$3
    [ "$actual" = "$expected" ] || fail "$label: expected '$expected', got '$actual'"
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null
STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

mkdir -p "${VAULT}/1_draft/research" "${VAULT}/2_knowledge/research"

cat > "${VAULT}/1_draft/research/sqlite-fts.md" <<'EOF'
---
id: "mem_promote_001"
title: "SQLite FTS"
description: "Promotable draft."
status: "pending"
tags:
  - research
version: 1
created: "2026-06-06"
---
# SQLite FTS

Draft body.
EOF

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/sqlite-fts.md" --to 2_knowledge --approved-by "reviewer" --json)
case "$out" in
    *'"ok":true'*) ;;
    *) fail "expected json promote success: $out" ;;
esac

target="${VAULT}/2_knowledge/research/sqlite-fts.md"
assert_file "$target"
assert_missing "${VAULT}/1_draft/research/sqlite-fts.md"
assert_contains "$target" 'strata: "2_knowledge"'
assert_contains "$target" 'status: "verified"'
assert_contains "$target" 'promoted_at: "'
assert_contains "$target" 'approved_by: "reviewer"'
assert_contains "$target" 'modified_by: "reviewer"'

DB="${VAULT}/0_core/db/strata.db"
target_index=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '2_knowledge/research/sqlite-fts.md' AND status = 'verified';")
assert_eq "$target_index" "1" "target indexed"
"$STRATA_BIN" refresh --vault "$VAULT" >/dev/null
target_id=$(/usr/bin/sqlite3 "$DB" "SELECT id FROM memory_index WHERE path = '2_knowledge/research/sqlite-fts.md';")
assert_eq "$target_id" "mem_promote_001" "target logical ID"

cat > "${VAULT}/1_draft/research/missing-approver.md" <<'EOF'
---
title: "Missing Approver"
description: "Must not promote without approval."
status: "pending"
tags:
  - research
---
# Missing Approver
EOF
if "$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/missing-approver.md" --to 2_knowledge >/dev/null 2>&1; then
    fail "expected missing approver promotion to fail"
fi
assert_file "${VAULT}/1_draft/research/missing-approver.md"
assert_missing "${VAULT}/2_knowledge/research/missing-approver.md"

cat > "${VAULT}/1_draft/research/duplicate-id.md" <<'EOF'
---
id: "mem_promote_001"
title: "Duplicate ID"
description: "Must not create a second promoted document."
status: "pending"
tags:
  - research
---
# Duplicate ID
EOF

DUPLICATE_JSON=$(mktemp "${TMP_ROOT}/rust-promote-duplicate-XXXXXXXX")
if "$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/duplicate-id.md" --to 2_knowledge --approved-by "reviewer" --json > "$DUPLICATE_JSON" 2>/dev/null; then
    fail "expected duplicate document ID promotion to fail"
fi
assert_contains "$DUPLICATE_JSON" '"ok":false'
assert_contains "$DUPLICATE_JSON" '"error":"duplicate_document_id"'
rm -f "$DUPLICATE_JSON"
assert_file "${VAULT}/1_draft/research/duplicate-id.md"
assert_missing "${VAULT}/2_knowledge/research/duplicate-id.md"

cat > "${VAULT}/2_knowledge/research/conflict.md" <<'EOF'
---
title: "Existing Conflict"
description: "Existing target."
status: "verified"
tags:
  - research
sources:
  - "../../1_draft/_archived/research/existing.md"
---
# Existing
EOF

cat > "${VAULT}/1_draft/research/conflict.md" <<'EOF'
---
title: "Duplicate"
description: "Should fail because target exists."
status: "pending"
tags:
  - research
---
# Duplicate
EOF

if "$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/conflict.md" --to 2_knowledge --approved-by "reviewer" >/dev/null 2>&1; then
    fail "expected overwrite promotion to fail"
fi
assert_file "${VAULT}/1_draft/research/conflict.md"

"$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/conflict.md" --to 2_knowledge --approved-by "reviewer" --new-slug duplicate-note >/dev/null
assert_file "${VAULT}/2_knowledge/research/duplicate-note.md"
assert_missing "${VAULT}/1_draft/research/conflict.md"

mkdir -p "${VAULT}/1_draft/trading"
cat > "${VAULT}/1_draft/trading/website-source.md" <<'EOF'
---
title: "Website Source"
description: "Promote into a concrete knowledge room."
status: "pending"
tags:
  - research
---
# Website Source
EOF

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/trading/website-source.md" --to 2_knowledge/entity/website --approved-by "reviewer" --json)
case "$out" in
    *'"target":"2_knowledge/entity/website/website-source.md"'*) ;;
    *) fail "expected concrete room target: $out" ;;
esac
assert_file "${VAULT}/2_knowledge/entity/website/website-source.md"
assert_missing "${VAULT}/1_draft/trading/website-source.md"
assert_contains "${VAULT}/2_knowledge/entity/website/website-source.md" 'strata: "2_knowledge"'

cat > "${VAULT}/1_draft/research/intelligence-skill.md" <<'EOF'
---
title: "Intelligence Skill"
description: "Promote into a concrete intelligence room."
status: "pending"
tags:
  - skill
---
# Intelligence Skill
EOF

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/intelligence-skill.md" --to 3_intelligence/skill/trading --approved-by "reviewer" --new-slug price-fetch-note --json)
case "$out" in
    *'"target":"3_intelligence/skill/trading/price-fetch-note.md"'*) ;;
    *) fail "expected concrete intelligence target: $out" ;;
esac
assert_file "${VAULT}/3_intelligence/skill/trading/price-fetch-note.md"
assert_missing "${VAULT}/1_draft/research/intelligence-skill.md"
assert_contains "${VAULT}/3_intelligence/skill/trading/price-fetch-note.md" 'strata: "3_intelligence"'

cat > "${VAULT}/1_draft/research/unsafe.md" <<'EOF'
---
title: "Unsafe"
description: "Unsafe target should be rejected."
status: "pending"
tags:
  - research
---
# Unsafe
EOF

if "$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/unsafe.md" --to 2_knowledge/../3_intelligence --approved-by "reviewer" >/dev/null 2>&1; then
    fail "expected unsafe promotion target to fail"
fi
assert_file "${VAULT}/1_draft/research/unsafe.md"
assert_missing "${VAULT}/3_intelligence/unsafe.md"

printf 'ok - rust promote passed\n'
