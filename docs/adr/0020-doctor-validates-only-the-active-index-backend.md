# Doctor validates only the active index backend

`strata doctor` will treat the configured active index backend as required health state and report the inactive backend only as informational capability. Doctor will not create, migrate, rebuild, or query the inactive backend's database, avoiding hidden state changes and irrelevant failures.
