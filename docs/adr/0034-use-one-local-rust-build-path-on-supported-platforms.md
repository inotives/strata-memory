# Use one local Rust build path on supported platforms

When no release binary is already present, `install.sh` will run the same local Cargo release build on Linux and Apple Silicon macOS, then install that binary through the existing managed-file path. Installation fails with a clear prerequisite message when Cargo is unavailable; Strata will not maintain separate platform-specific build behavior.
