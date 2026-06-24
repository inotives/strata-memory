# Test both index backends through one contract suite

SQLite and Turso will run through one parameterized backend contract suite covering migrations, indexing, cleanup, search, semantic behavior, output contracts, and failures. Adapter-specific tests are limited to behavior that cannot be expressed portably, such as backend migration syntax, native FTS/vector operations, and lock errors; Strata will not maintain duplicate end-to-end suites.
