# Support Cargo offline install without vendoring dependencies

The installer may use Cargo's normal registry access and local cache when building Strata. An environment-controlled offline mode will pass Cargo's `--offline` flag for machines with cached dependencies, but the repository will not vendor Turso or the complete Rust dependency graph during this phase.
