# Turso 0.6.1 Evaluation

- Platform: `Darwin/arm64`
- SQLite remains the default backend.
- Datasets: committed synthetic fixture plus an approved temporary copy of the private vault.
- Private-vault results contain aggregate counts and timings only.

## Correctness

| Query | SQLite top | Turso top | Top-10 overlap |
|---|---|---|---:|
| title | `2_knowledge/research/quantum-ledger.md` | `2_knowledge/research/quantum-ledger.md` | 100% |
| description | `2_knowledge/research/quantum-ledger.md` | `2_knowledge/research/quantum-ledger.md` | 100% |
| body | `2_knowledge/research/amber-compass.md` | `2_knowledge/research/amber-compass.md` | 100% |
| exact_phrase | `2_knowledge/research/quantum-ledger.md` | `2_knowledge/research/quantum-ledger.md` | 100% |
| metadata | `2_knowledge/research/harbor-protocol.md` | `2_knowledge/research/harbor-protocol.md` | 100% |
| archived_excluded | `(none)` | `(none)` | 100% |
| archived_included | `2_knowledge/research/blue-archive.md` | `2_knowledge/research/blue-archive.md` | 100% |
| no_match | `(none)` | `(none)` | 100% |
| semantic | `2_knowledge/research/silent-engine.md` | `2_knowledge/research/silent-engine.md` | 100% |
| mixed | `2_knowledge/research/echo-garden.md` | `2_knowledge/research/echo-garden.md` | 100% |

## Aggregate Measurements

| Metric | SQLite | Turso | Ratio |
|---|---:|---:|---:|
| Full refresh | 6.41 ms (6.27-6.92) | 30.15 ms (29.07-30.60) | 4.71x |
| FTS query | 4.35 ms (3.87-7.02) | 4.59 ms (4.19-5.23) | 1.06x |
| Hybrid query | 4.52 ms (4.21-5.16) | 5.30 ms (4.93-5.71) | 1.17x |
| Index size | 131072 bytes | 1046488 bytes | 7.98x |

- Interrupted refresh recovery: pass
- Search timing: one warm-up plus ten runs per curated query.
- Refresh timing: one warm-up plus three runs per backend.

## Linux Container Validation

- Date: 2026-06-25
- Image: `rust:bookworm`
- `linux/arm64`: core SQLite/Turso smoke suite passed.
- `linux/amd64`: core SQLite/Turso smoke suite passed under emulation.

## Private-Vault Copy Validation

- SQLite refresh completed for 1,721 documents and SQLite FTS search passed.
- Turso refresh completed for the same 1,721 documents.
- Turso semantic refresh created 24,967 embeddings: 190 descriptions and 24,777 sections.
- Turso FTS and hybrid search passed; semantic status reported the vector index ready.
- The initial Turso refresh took approximately 75 seconds.
- A repeated Turso refresh after semantic embeddings existed exceeded 337 seconds and was interrupted.
- After interruption, Turso FTS, hybrid search, and all 24,967 embeddings remained available, confirming transaction rollback preserved the previous valid index.
- SQLite occupied 49.77 MiB. Turso occupied 85.01 MiB plus a 190.23 MiB WAL at the observation point.
- The installed private vault remained configured for SQLite and no Turso database was created in it.
- `strata doctor` reported the same pre-existing vault content error on both backends: 68 durable link errors.

## Failed Gates

- refresh latency ratio 4.71 exceeds 2x
- database size ratio 7.98 exceeds 2x
- private-vault repeated rebuild exceeded 337 seconds after embeddings existed
- private-vault Turso database plus WAL materially exceeded SQLite size

## Verdict

continue-evaluation

Turso 0.6.1 is functionally usable but is not a SQLite replacement candidate. Keep it experimental and opt-in, keep SQLite as the default, and re-evaluate after the first upstream stable release intended for production use. The next evaluation should prioritize full and repeated rebuild latency, database and WAL size, and interruption recovery.
