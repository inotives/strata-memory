#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-index-backend-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null
STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

sqlite=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json)
case "$sqlite" in
    *'"backend":"sqlite"'*) ;;
    *) fail "expected SQLite backend metadata: $sqlite" ;;
esac

sed 's/backend: "sqlite"/backend: "turso"/' \
    "${VAULT}/0_core/config/configs.yaml" > "${VAULT}/0_core/config/configs.yaml.turso"
mv "${VAULT}/0_core/config/configs.yaml.turso" "${VAULT}/0_core/config/configs.yaml"

TURSO_MIGRATE=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json)
case "$TURSO_MIGRATE" in
    *'"backend":"turso"'*'"experimental":true'*'"applied":3'*) ;;
    *) fail "expected Turso migrations: $TURSO_MIGRATE" ;;
esac
[ -f "${VAULT}/0_core/db/strata-turso.db" ] || fail "expected Turso database file"

TURSO_SECOND=$("$STRATA_BIN" db-migrate --vault "$VAULT" --json)
case "$TURSO_SECOND" in
    *'"backend":"turso"'*'"applied":0'*) ;;
    *) fail "expected idempotent Turso migrations: $TURSO_SECOND" ;;
esac

cat > "${VAULT}/2_knowledge/concept/turso-search.md" <<'EOF'
---
title: "Turso Search"
description: "Embedded vector search evaluation."
status: "verified"
---
# Turso Search

Exact local semantic retrieval.
EOF

refresh=$("$STRATA_BIN" refresh --vault "$VAULT" --json)
case "$refresh" in
    *'"backend":"turso"'*'"indexed":'*) ;;
    *) fail "expected Turso refresh: $refresh" ;;
esac

search=$("$STRATA_BIN" search --vault "$VAULT" --query "vector search" --json)
case "$search" in
    *'"backend":"turso"'*'"mode":"fts"'*'2_knowledge/concept/turso-search.md'*) ;;
    *) fail "expected Turso FTS result: $search" ;;
esac

sed \
    -e 's/provider: ""/provider: "builtin-hash"/' \
    -e 's/model: ""/model: "hash-v1"/' \
    -e 's/embedding_dim: 0/embedding_dim: 64/' \
    "${VAULT}/0_core/config/configs.yaml" > "${VAULT}/0_core/config/configs.yaml.semantic"
mv "${VAULT}/0_core/config/configs.yaml.semantic" "${VAULT}/0_core/config/configs.yaml"

semantic=$("$STRATA_BIN" semantic-refresh --vault "$VAULT" --json)
case "$semantic" in
    *'"backend":"turso"'*'"indexed":'*) ;;
    *) fail "expected Turso semantic refresh: $semantic" ;;
esac

status=$("$STRATA_BIN" semantic-status --vault "$VAULT" --json)
case "$status" in
    *'"backend":"turso"'*'"experimental":true'*'"semantic_available":true'*) ;;
    *) fail "expected Turso semantic status: $status" ;;
esac

hybrid=$("$STRATA_BIN" search --vault "$VAULT" --query "local semantic retrieval" --hybrid --json)
case "$hybrid" in
    *'"backend":"turso"'*'"mode":"hybrid"'*'2_knowledge/concept/turso-search.md'*) ;;
    *) fail "expected Turso hybrid result: $hybrid" ;;
esac

doctor=$("$STRATA_BIN" doctor --vault "$VAULT" --json)
case "$doctor" in
    *'"ok":true'*'"backend":"turso"'*'"experimental":true'*'"name":"index_backend"'*) ;;
    *) fail "expected experimental Turso doctor output: $doctor" ;;
esac

printf 'ok - rust index backend passed\n'
