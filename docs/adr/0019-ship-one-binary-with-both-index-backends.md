# Ship one binary with both index backends

The normal `strata` binary will compile and ship both SQLite and Turso index backends, with vault configuration selecting the active one. Strata will not create feature-gated backend binaries or separate distributions during the evaluation because that would duplicate installation, release, and test paths before Turso's replacement value is proven.
