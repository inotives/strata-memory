# Use a shallow index module layout

Index code will move incrementally from `main.rs` into `src/index/mod.rs`, `src/index/model.rs`, `src/index/sqlite.rs`, and `src/index/turso.rs`. The module owns backend selection and complete index operations, while `main.rs` retains command dispatch and output formatting; no deeper adapter, repository, service, or factory hierarchy is introduced.
