#!/usr/bin/env bash

strata_have() {
    command -v "$1" >/dev/null 2>&1
}

strata_check_bootstrap_dependencies() {
    local missing=""
    local dep

    for dep in bash sqlite3 awk sed find sort mktemp cksum date; do
        if ! strata_have "$dep"; then
            missing="${missing} ${dep}"
        fi
    done

    if [ -n "$missing" ]; then
        printf '%s\n' "Missing bootstrap dependencies:${missing}" >&2
        printf '%s\n' "Install the missing tools, then rerun the command." >&2
        return 1
    fi

    return 0
}

strata_check_full_dependencies() {
    local missing=""
    local dep

    for dep in jq yq; do
        if ! strata_have "$dep"; then
            missing="${missing} ${dep}"
        fi
    done

    if [ -n "$missing" ]; then
        printf '%s\n' "Missing full-mode dependencies:${missing}" >&2
        printf '%s\n' "Full mode requires jq and yq. Install them manually; Strata-Memory will not auto-install dependencies." >&2
        return 1
    fi

    return 0
}
