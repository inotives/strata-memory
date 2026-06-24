# Use an operation-level index backend module

Strata will select SQLite or Turso through one small internal backend module that exposes complete operations such as migrate, index, search, semantic refresh, and semantic status. The seam will not mirror connection, transaction, statement, or row APIs; backend-specific SQL and async details remain hidden so callers and contract tests use one deep interface.
