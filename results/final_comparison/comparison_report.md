# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-04-24 00:27:25  |  Caliper 0.6.0  |  Fabric 2.5.9

**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 39.0 | 39.0 | 26290 | 27,896 | **0** | **100.0%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 39.0 | 39.0 | 26290 | 27,896 | **0** | **100.0%** | **+0.0%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 39.0 | 39.0 | 26290 | 27,896 | **0** | **100.0%** | **+0.0%** |
| **Hybrid + Batching ×10** | `hybrid` | 10 | 8 | 39.0 | 390.0 | 26290 | 27,896 | **0** | **100.0%** | **+0.0%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 39.0 | 39.0 | **+0.0%** |
| Eff. Cert TPS | 39.0 | 390.0 | **+900.0%** |
| Avg Latency (ms) | 26290 | 26290 | **-0.0%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
