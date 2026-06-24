#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    printf '%s\n' 'macOS smoke requires native Apple Silicon (Darwin/arm64)' >&2
    exit 1
fi

for test_script in \
    install_test.sh \
    rust_init_test.sh \
    rust_index_test.sh \
    rust_search_test.sh \
    rust_semantic_refresh_test.sh \
    rust_semantic_status_test.sh \
    rust_doctor_test.sh
do
    bash "${ROOT}/test/${test_script}"
done

printf 'ok - native Apple Silicon smoke passed\n'
