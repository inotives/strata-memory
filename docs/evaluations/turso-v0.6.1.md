# Turso 0.6.1 Evaluation

- Platform: `Darwin/arm64`
- SQLite remains the default backend.
- Dataset: committed synthetic fixture only; private-vault benchmarking was not run.

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

## Failed Gates

- refresh latency ratio 4.71 exceeds 2x
- database size ratio 7.98 exceeds 2x
- Linux validation pending

## Verdict

continue-evaluation
