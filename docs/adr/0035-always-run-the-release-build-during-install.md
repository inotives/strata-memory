# Always run the release build during install

`install.sh` will run `cargo build --release` before installing Strata on supported platforms rather than trusting an existing `target/release/strata`. Cargo's incremental build keeps repeat installs efficient while ensuring the installed binary reflects the current source and lockfile.
