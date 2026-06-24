# Remove a rejected Turso backend if it cannot stay healthy

A `reject-for-now` verdict may retain the opt-in Turso backend only when it remains buildable, its enabled tests pass except documented upstream gaps, and its maintenance cost is low. Otherwise Phase 6 removes the backend code and configuration option while preserving the versioned evaluation report and ADR history; Strata will not carry a permanently broken experimental path.
