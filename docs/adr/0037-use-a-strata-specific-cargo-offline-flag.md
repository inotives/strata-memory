# Use a Strata-specific Cargo offline flag

`install.sh` will recognize `STRATA_CARGO_OFFLINE=1` and add `--offline` to the Cargo release build. A generic `OFFLINE` variable will not be used because it could unintentionally alter unrelated installation behavior.
