# Pin the Turso evaluation version

The Turso backend will use an exact released crate version and commit the resulting `Cargo.lock`. Strata will not depend on Turso's Git `main` branch or a loose version range; upgrading Turso requires an explicit change that reruns backend contract, stability, and performance evaluation.
