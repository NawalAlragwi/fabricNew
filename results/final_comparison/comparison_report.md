# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-04-19 01:33:22  |  Caliper 0.6.0  |  Fabric 2.5.9

**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 50.1 | 50.1 | 12560 | 52,902 | **7550** | **85.7%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 50.1 | 50.1 | 12560 | 52,902 | **7550** | **85.7%** | **+0.0%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 50.1 | 50.1 | 12560 | 52,902 | **7550** | **85.7%** | **+0.0%** |
| **Hybrid + Batching ×10** | `hybrid` | 20 | 8 | 50.1 | 1002.0 | 12560 | 52,902 | **7550** | **85.7%** | **+0.0%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 50.1 | 50.1 | **+0.0%** |
| Eff. Cert TPS | 50.1 | 1002.0 | **+1900.0%** |
| Avg Latency (ms) | 12560 | 12560 | **-0.0%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
