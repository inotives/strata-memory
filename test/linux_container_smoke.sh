#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PLATFORM=${1:-linux/arm64}

case "$PLATFORM" in
    linux/arm64|linux/amd64) ;;
    *)
        printf '%s\n' "usage: $0 [linux/arm64|linux/amd64]" >&2
        exit 2
        ;;
esac

docker run --rm \
    --platform "$PLATFORM" \
    --mount "type=bind,src=${ROOT},dst=/src,readonly" \
    rust:bookworm \
    bash -ceu '
        apt-get update -qq
        apt-get install -y -qq sqlite3 >/dev/null
        cp -a /src /work
        cd /work
        for test_script in \
            install_test.sh \
            rust_init_test.sh \
            rust_index_backend_test.sh \
            rust_index_test.sh \
            rust_search_test.sh \
            rust_semantic_refresh_test.sh \
            rust_semantic_status_test.sh \
            rust_doctor_test.sh
        do
            if bash "test/${test_script}" >/tmp/strata-test.log 2>&1; then
                printf "ok - %s\n" "$test_script"
            else
                cat /tmp/strata-test.log >&2
                exit 1
            fi
        done
    '

printf 'ok - Linux container smoke passed (%s)\n' "$PLATFORM"
