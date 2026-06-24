# Confine async execution to the Turso backend boundary

Strata will add a minimal single-thread Tokio runtime for Turso's asynchronous Rust API and keep CLI parsing, Markdown processing, filesystem traversal, and SQLite execution synchronous. Async will not spread across the application unless a later measured need justifies it.
