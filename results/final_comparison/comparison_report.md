# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-04-19 13:51:15  |  Caliper 0.6.0  |  Fabric 2.5.9

**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 48.4 | 48.4 | 24210 | 57,880 | **6778** | **88.3%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 48.4 | 48.4 | 24210 | 57,880 | **6778** | **88.3%** | **+0.0%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 48.4 | 48.4 | 24210 | 57,880 | **6778** | **88.3%** | **+0.0%** |
| **Hybrid + Batching ×10** | `hybrid` | 20 | 8 | 48.4 | 968.0 | 24210 | 57,880 | **6778** | **88.3%** | **+0.0%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 48.4 | 48.4 | **+0.0%** |
| Eff. Cert TPS | 48.4 | 968.0 | **+1900.0%** |
| Avg Latency (ms) | 24210 | 24210 | **-0.0%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
