# Implement Turso as a complete index backend

The Turso evaluation will implement the same user-visible indexing and search contract as SQLite behind `index.backend: turso`, rather than a disposable benchmark prototype. The phase will not add automatic fallback or promote Turso to the default; its result is evidence about parity, reliability, performance, and whether replacing SQLite is justified.
