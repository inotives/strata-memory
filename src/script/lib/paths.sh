#!/usr/bin/env bash

strata_vault() {
    if [ -n "${STRATA_VAULT:-}" ]; then
        printf '%s\n' "$STRATA_VAULT"
    else
        printf '%s\n' "${HOME}/.strata-memory"
    fi
}

strata_core() {
    printf '%s/0_core\n' "$(strata_vault)"
}

strata_db_path() {
    printf '%s/db/strata.db\n' "$(strata_core)"
}

strata_config_cache_path() {
    printf '%s/cache/config.compiled.json\n' "$(strata_core)"
}

strata_migrations_dir() {
    printf '%s/db/migrations\n' "$(strata_core)"
}
