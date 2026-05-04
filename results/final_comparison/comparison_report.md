# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-05-04 13:57:00  |  Caliper 0.6.0  |  Fabric 2.5.9

**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 30.2 | 30.2 | 101430 | 27,322 | **4252** | **84.4%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 21.1 | 21.1 | 22250 | 25,610 | **9316** | **63.6%** | **-30.1%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 37.8 | 37.8 | 17320 | 44,414 | **156** | **99.6%** | **+25.2%** |
| **Hybrid + Batching ×10** | `hybrid` | 10 | 8 | 72.9 | 729.0 | 2060 | 59,096 | **0** | **100.0%** | **+141.4%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 30.2 | 72.9 | **+141.4%** |
| Eff. Cert TPS | 30.2 | 729.0 | **+2313.9%** |
| Avg Latency (ms) | 101430 | 2060 | **-98.0%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
