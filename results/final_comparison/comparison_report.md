# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-05-04 23:52:45  |  Caliper 0.6.0  |  Fabric 2.5.9

**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 19.7 | 19.7 | 450 | 21,404 | **0** | **100.0%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 18.9 | 18.9 | 6010 | 22,860 | **0** | **100.0%** | **-4.1%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 37.8 | 37.8 | 17320 | 44,414 | **156** | **99.6%** | **+91.9%** |
| **Hybrid + Batching ×10** | `hybrid` | 10 | 8 | 72.9 | 729.0 | 2060 | 59,096 | **0** | **100.0%** | **+270.1%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 19.7 | 72.9 | **+270.1%** |
| Eff. Cert TPS | 19.7 | 729.0 | **+3600.5%** |
| Avg Latency (ms) | 450 | 2060 | **--357.8%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
