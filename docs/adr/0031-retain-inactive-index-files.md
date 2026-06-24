# Retain inactive index files

Switching `index.backend` will leave the inactive backend's database untouched so users can switch back without losing derived state. `strata doctor` may report the inactive database path, size, and age as informational data, but Strata will not refresh or delete it automatically; cleanup is deferred until disk usage is a measured problem.
