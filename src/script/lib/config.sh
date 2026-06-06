#!/usr/bin/env bash

strata_config_path() {
    printf '%s/config/configs.yaml\n' "$(strata_core)"
}

strata_config_exists() {
    [ -f "$(strata_config_path)" ]
}
