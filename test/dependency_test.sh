#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BASH_BIN=$(command -v bash)

output=$(PATH=/nonexistent "$BASH_BIN" -c ". '${ROOT}/src/script/lib/platform.sh'; strata_check_bootstrap_dependencies" 2>&1 >/dev/null || true)
case "$output" in
    *"Missing bootstrap dependencies:"*"Install the missing tools"*) ;;
    *) printf 'not ok - missing bootstrap dependency message\n%s\n' "$output" >&2; exit 1 ;;
esac

output=$(PATH=/nonexistent "$BASH_BIN" -c ". '${ROOT}/src/script/lib/platform.sh'; strata_check_full_dependencies" 2>&1 >/dev/null || true)
case "$output" in
    *"Missing full-mode dependencies:"*"jq"*"yq"*"will not auto-install dependencies"*) ;;
    *) printf 'not ok - missing full dependency message\n%s\n' "$output" >&2; exit 1 ;;
esac

printf 'ok - dependency checks passed\n'
