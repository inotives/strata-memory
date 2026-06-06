#!/usr/bin/env bash

strata_log_info() {
    printf '%s\n' "info: $*" >&2
}

strata_log_warn() {
    printf '%s\n' "warn: $*" >&2
}

strata_log_error() {
    printf '%s\n' "error: $*" >&2
}
