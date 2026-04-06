# BCMS Four-Scenario Academic Benchmark Comparison
> Generated: 2026-03-29 21:00:43  |  Caliper 0.6.0  |  Fabric 2.5.9

**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% |
|:--|:--|:--:|--:|--:|--:|--:|--:|--:|
| **S1: SHA-256** | `sha256` | 1 | 32.4 | 32.4 | 1940 | 4,725 | **0** | **100.0%** |
| **S2: BLAKE3** | `blake3` | 1 | 34.5 | 34.5 | 1820 | 4,950 | **0** | **100.0%** |
| **S3: Hybrid** | `hybrid-sha256-blake3` | 1 | 38.2 | 38.2 | 1710 | 5,295 | **0** | **100.0%** |
| **S4: Hybrid+Batch** | `hybrid-sha256-blake3` | 10 | 95.0 | 950.0 | 1420 | 11,541 | **0** | **100.0%** |

## Key Improvement: S1→S4
| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 32.4 | 95.0 | **+193%** |
| Eff. Cert TPS | 32.4 | 475.0 | **+1,366%** |
| Avg Latency (ms) | 1,940 | 1,420 | **-27%** |
| Consensus/100 | 100 | 20 | **-80%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
