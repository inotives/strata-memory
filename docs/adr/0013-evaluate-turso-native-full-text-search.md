# Evaluate Turso native full-text search

The Turso backend will use Turso's native full-text-search capability rather than implementing portable table scans or a separate search engine. If native Turso FTS cannot preserve Strata's ranking, filtering, snippet, and stability contracts, the evaluation will record Turso as not yet suitable to replace SQLite instead of masking the gap with custom search code.
