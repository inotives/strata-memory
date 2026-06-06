#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT="${ROOT}/test/tmp"
mkdir -p "$TMP_ROOT"
VAULT=$(mktemp -d "${TMP_ROOT}/privacy-review-test-XXXXXXXX")
trap 'rm -rf "$VAULT"' EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack=$1
    local needle=$2
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "expected '$needle' in '$haystack'" ;;
    esac
}

"${ROOT}/install.sh" --vault "$VAULT" >/dev/null

mkdir -p "${VAULT}/1_draft/research" "${VAULT}/2_knowledge/concept"

cat > "${VAULT}/1_draft/research/private.md" <<'EOF'
---
title: "Private"
tags:
  - research
---
# Private

Local path: /home/alice/project/private.txt
Link: [secret](file:///home/alice/.ssh/id_rsa)
OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456
password: "abcdefghijklmnopqrstuvwxyz1234567890"
-----BEGIN OPENSSH PRIVATE KEY-----
EOF

cat > "${VAULT}/2_knowledge/concept/public.md" <<'EOF'
---
title: "Public"
tags:
  - research
sources: []
---
# Public

No private data here.
EOF

out=$("${VAULT}/0_core/script/privacy-review.sh" --vault "$VAULT" --json)
assert_contains "$out" '"ok":true'
assert_contains "$out" '"reason":"absolute_home_path"'
assert_contains "$out" '"reason":"file_url"'
assert_contains "$out" '"reason":"env_secret"'
assert_contains "$out" '"reason":"api_key_like"'
assert_contains "$out" '"reason":"private_ssh_key"'

if ! "${VAULT}/0_core/script/privacy-review.sh" --vault "$VAULT" >/dev/null; then
    fail "privacy review should be warning-only"
fi

printf 'ok - privacy review passed\n'
