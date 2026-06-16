#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-semantic-refresh-test-XXXXXXXX")
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

perl -0pi -e 's/semantic:\n  provider: ""\n  model: ""\n  embedding_dim: 0\n/semantic:\n  provider: "builtin-hash"\n  model: "hash-v1"\n  embedding_dim: 64\n/' "$VAULT/0_core/config/configs.yaml"

mkdir -p "${VAULT}/2_knowledge/concept" "${VAULT}/1_draft/_archived/research"

cat > "${VAULT}/2_knowledge/concept/vector-alpha.md" <<'EOF'
---
title: "Vector Alpha"
description: "Local vector refresh embeds durable descriptions."
strata: "2_knowledge"
status: "verified"
tags:
  - search
sources:
  - "../../1_draft/_archived/research/vector-alpha.md"
version: 1
---
# Embedding Runtime

Hybrid search combines exact FTS matches with local hashed token vectors.
EOF

cat > "${VAULT}/2_knowledge/concept/empty-description.md" <<'EOF'
---
title: "Empty Description"
description: ""
strata: "2_knowledge"
status: "verified"
tags:
  - search
sources:
  - "../../1_draft/_archived/research/empty-description.md"
version: 1
---
# Empty Description

Sections are still embedded when descriptions are empty.
EOF

cat > "${VAULT}/1_draft/_archived/research/archived-vector.md" <<'EOF'
---
title: "Archived Vector"
description: "archived vector result"
status: "archived"
---
# Archived

archived vector content
EOF

STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
SQLITE_BIN="${SQLITE_BIN:-/usr/bin/sqlite3}"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

"$STRATA_BIN" refresh --vault "$VAULT" >/dev/null

out=$("$STRATA_BIN" semantic-refresh --vault "$VAULT" --json)
assert_contains "$out" '"ok":true' "semantic refresh json ok"
assert_contains "$out" '"provider":"builtin-hash"' "semantic refresh provider"
assert_contains "$out" '"model":"hash-v1"' "semantic refresh model"
assert_contains "$out" '"embedding_dim":64' "semantic refresh dim"
assert_contains "$out" '"descriptions":2' "empty descriptions skipped"
assert_contains "$out" '"sections":4' "sections embedded"

DB="${VAULT}/0_core/db/strata.db"
empty_description_count=$("$SQLITE_BIN" "$DB" "SELECT count(*) FROM semantic_embeddings WHERE path = '2_knowledge/concept/empty-description.md' AND target_type = 'description';")
[ "$empty_description_count" = "0" ] || fail "empty descriptions should not be embedded"

before_hash=$("$SQLITE_BIN" "$DB" "SELECT content_hash FROM semantic_embeddings WHERE path = '2_knowledge/concept/vector-alpha.md' AND target_type = 'description';")
perl -0pi -e 's/Local vector refresh embeds durable descriptions\./Local vector refresh rebuilds changed durable descriptions./' "$VAULT/2_knowledge/concept/vector-alpha.md"
"$STRATA_BIN" refresh --vault "$VAULT" >/dev/null
"$STRATA_BIN" semantic-refresh --vault "$VAULT" >/dev/null
after_hash=$("$SQLITE_BIN" "$DB" "SELECT content_hash FROM semantic_embeddings WHERE path = '2_knowledge/concept/vector-alpha.md' AND target_type = 'description';")
[ "$before_hash" != "$after_hash" ] || fail "description content hash should change after edit"

status_json=$("$STRATA_BIN" semantic-status --vault "$VAULT" --json)
assert_contains "$status_json" '"semantic_available":true' "semantic status available"
assert_contains "$status_json" '"runtime_available":true' "semantic runtime available"
assert_contains "$status_json" '"vector_index_ready":true' "semantic vector ready"

hybrid_json=$("$STRATA_BIN" search --vault "$VAULT" --query vector --hybrid --json --limit 5)
assert_contains "$hybrid_json" '"requested_mode":"hybrid"' "hybrid requested"
assert_contains "$hybrid_json" '"mode":"hybrid"' "hybrid actual"
assert_contains "$hybrid_json" '"warnings":[]' "hybrid no fallback warning"
assert_contains "$hybrid_json" '"path":"2_knowledge/concept/vector-alpha.md"' "hybrid durable result"
case "$hybrid_json" in
    *"1_draft/_archived/research/archived-vector.md"*) fail "archived semantic result should be excluded by default" ;;
esac

archived_hybrid=$("$STRATA_BIN" search --vault "$VAULT" --query vector --hybrid --include-archived --paths-only --limit 10)
assert_contains "$archived_hybrid" "1_draft/_archived/research/archived-vector.md" "hybrid include archived"

printf 'ok - rust semantic refresh passed\n'
