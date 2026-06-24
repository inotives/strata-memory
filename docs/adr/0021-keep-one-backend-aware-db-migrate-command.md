# Keep one backend-aware db-migrate command

`strata db-migrate` will migrate only the configured active index backend and retain its existing command name. JSON output will identify `backend`, `db`, and `applied`; Strata will not add Turso-specific migration commands because backend selection already belongs to vault configuration.
