#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/rust-privacy-review-test-XXXXXXXX")
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
STRATA_BIN="${ROOT}/src/rust/strata/target/debug/strata"
cargo build --manifest-path "${ROOT}/src/rust/strata/Cargo.toml" >/dev/null

mkdir -p "${VAULT}/1_draft/research" "${VAULT}/2_knowledge/concept" "${VAULT}/3_intelligence/report"

cat > "${VAULT}/1_draft/research/private.md" <<'EOF'
---
title: "Private"
description: ""
tags:
  - research
---
# Private

Local path: /home/example/secret.txt
Local URL: file:///Users/example/notes.md
export ACCESS_TOKEN=abcdefghijklmnopqrstuvwxyz
password: abcdefghijklmnopqrstuvwxyz123456
-----BEGIN OPENSSH PRIVATE KEY-----
token: sk-abcdefghijklmnopqrstuvwxyz
EOF

cat > "${VAULT}/2_knowledge/concept/public.md" <<'EOF'
---
title: "Public"
description: "No private data here."
tags:
  - concept
sources:
  - "../../1_draft/_archived/concept/public.md"
---
# Public

No private data here.
EOF

cat > "${VAULT}/3_intelligence/report/.env" <<'EOF'
PRIVATE_KEY=abcdefghijklmnopqrstuvwxyz
EOF

cat > "${VAULT}/AGENTS.md" <<'EOF'
# Agents

See /root/.ssh/id_rsa before publishing.
EOF

out=$("$STRATA_BIN" privacy-review --vault "$VAULT" --json)
assert_contains "$out" '"ok":true' "json ok"
assert_contains "$out" '"reason":"absolute_home_path"' "absolute home"
assert_contains "$out" '"reason":"file_url"' "file url"
assert_contains "$out" '"reason":"env_secret"' "env secret"
assert_contains "$out" '"reason":"api_key_like"' "api key"
assert_contains "$out" '"reason":"private_ssh_key"' "private key"
assert_contains "$out" '"path":"3_intelligence/report/.env"' ".env scanned"
assert_contains "$out" '"path":"AGENTS.md"' "AGENTS scanned"

if ! "$STRATA_BIN" privacy-review --vault "$VAULT" >/dev/null; then
    fail "privacy review should be warning-only"
fi

printf 'ok - rust privacy review passed\n'
