# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-05-04 22:26:44  |  Caliper 0.6.0  |  Fabric 2.5.9

**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 19.9 | 19.9 | 500 | 17,698 | **0** | **100.0%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 9.8 | 9.8 | 34260 | 31,602 | **11240** | **64.4%** | **-50.8%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 37.8 | 37.8 | 17320 | 44,414 | **156** | **99.6%** | **+89.9%** |
| **Hybrid + Batching ×10** | `hybrid` | 10 | 8 | 72.9 | 729.0 | 2060 | 59,096 | **0** | **100.0%** | **+266.3%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 19.9 | 72.9 | **+266.3%** |
| Eff. Cert TPS | 19.9 | 729.0 | **+3563.3%** |
| Avg Latency (ms) | 500 | 2060 | **--312.0%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
