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

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/sqlite-fts.md" --to 2_knowledge --json)
case "$out" in
    *'"ok":true'*) ;;
    *) fail "expected json promote success: $out" ;;
esac

target="${VAULT}/2_knowledge/research/sqlite-fts.md"
archive="${VAULT}/1_draft/_archived/research/sqlite-fts.md"
assert_file "$target"
assert_file "$archive"
assert_missing "${VAULT}/1_draft/research/sqlite-fts.md"
assert_contains "$target" 'strata: "2_knowledge"'
assert_contains "$target" 'status: "verified"'
assert_contains "$target" 'sources:'
assert_contains "$target" '1_draft/_archived/research/sqlite-fts.md'
assert_contains "$target" 'promoted_at: "'
assert_contains "$archive" 'status: "archived"'
assert_contains "$archive" 'archived_from: "1_draft/research/sqlite-fts.md"'

cat > "${VAULT}/1_draft/research/2026-06-07__dated-research.md" <<'EOF'
---
title: "Dated Research"
description: "Promotable dated research draft."
status: "pending"
tags:
  - research
---
# Dated Research
EOF

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/2026-06-07__dated-research.md" --to 2_knowledge --json)
case "$out" in
    *'"target":"2_knowledge/research/2026-06-07__dated-research.md"'*) ;;
    *) fail "expected dated research filename to be preserved: $out" ;;
esac
assert_file "${VAULT}/2_knowledge/research/2026-06-07__dated-research.md"
assert_file "${VAULT}/1_draft/_archived/research/2026-06-07__dated-research.md"
assert_missing "${VAULT}/1_draft/research/2026-06-07__dated-research.md"

DB="${VAULT}/0_core/db/strata.db"
target_index=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '2_knowledge/research/sqlite-fts.md' AND status = 'verified';")
assert_eq "$target_index" "1" "target indexed"
archive_index=$(/usr/bin/sqlite3 "$DB" "SELECT count(*) FROM memory_index WHERE path = '1_draft/_archived/research/sqlite-fts.md' AND status = 'archived';")
assert_eq "$archive_index" "1" "archive indexed"

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

if "$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/conflict.md" --to 2_knowledge >/dev/null 2>&1; then
    fail "expected overwrite promotion to fail"
fi
assert_file "${VAULT}/1_draft/research/conflict.md"

"$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/conflict.md" --to 2_knowledge --new-slug duplicate-note >/dev/null
assert_file "${VAULT}/2_knowledge/research/duplicate-note.md"
assert_file "${VAULT}/1_draft/_archived/research/conflict.md"

cat > "${VAULT}/1_draft/research/2026-06-08__rename-me.md" <<'EOF'
---
title: "Rename Me"
description: "Promotable dated research draft with a new slug."
status: "pending"
tags:
  - research
---
# Rename Me
EOF

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/2026-06-08__rename-me.md" --to 2_knowledge --new-slug renamed-research --json)
case "$out" in
    *'"target":"2_knowledge/research/2026-06-08__renamed-research.md"'*) ;;
    *) fail "expected new slug to preserve research date prefix: $out" ;;
esac
assert_file "${VAULT}/2_knowledge/research/2026-06-08__renamed-research.md"
assert_file "${VAULT}/1_draft/_archived/research/2026-06-08__rename-me.md"

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

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/trading/website-source.md" --to 2_knowledge/entity/website --json)
case "$out" in
    *'"target":"2_knowledge/entity/website/website-source.md"'*) ;;
    *) fail "expected concrete room target: $out" ;;
esac
assert_file "${VAULT}/2_knowledge/entity/website/website-source.md"
assert_file "${VAULT}/1_draft/_archived/trading/website-source.md"
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

out=$("$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/intelligence-skill.md" --to 3_intelligence/skill/trading --new-slug price-fetch-note --json)
case "$out" in
    *'"target":"3_intelligence/skill/trading/price-fetch-note.md"'*) ;;
    *) fail "expected concrete intelligence target: $out" ;;
esac
assert_file "${VAULT}/3_intelligence/skill/trading/price-fetch-note.md"
assert_file "${VAULT}/1_draft/_archived/research/intelligence-skill.md"
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

if "$STRATA_BIN" promote --vault "$VAULT" --source "${VAULT}/1_draft/research/unsafe.md" --to 2_knowledge/../3_intelligence >/dev/null 2>&1; then
    fail "expected unsafe promotion target to fail"
fi
assert_file "${VAULT}/1_draft/research/unsafe.md"
assert_missing "${VAULT}/3_intelligence/unsafe.md"

printf 'ok - rust promote passed\n'
