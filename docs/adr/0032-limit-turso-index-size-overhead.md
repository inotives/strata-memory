# Limit Turso index size overhead

The evaluation will measure both backend database sizes after equivalent full refresh and semantic indexing. Turso fails the replacement-candidate gate if `strata-turso.db` is larger than twice the equivalent SQLite index, because Strata's local-first vault should not accept unbounded derived-storage overhead.
