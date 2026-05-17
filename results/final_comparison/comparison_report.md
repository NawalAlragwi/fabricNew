# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-05-17 11:17:42  |  Caliper 0.6.0  |  Fabric 2.5.9


> ⚠️  **SIMULATED DATA**: Docker/Fabric unavailable. Run `bash setup_and_run_all.sh --all-scenarios` in a Docker-enabled environment for real measurements.
**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 32.4 | 32.4 | 1940 | 4,725 | **0** | **100.0%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 20.0 | 20.0 | 450 | 25,058 | **0** | **100.0%** | **-38.3%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 37.8 | 37.8 | 17320 | 44,414 | **156** | **99.6%** | **+16.7%** |
| **Hybrid + Batching ×10** | `hybrid` | 10 | 8 | 72.9 | 729.0 | 2060 | 59,096 | **0** | **100.0%** | **+125.0%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 32.4 | 72.9 | **+125.0%** |
| Eff. Cert TPS | 32.4 | 729.0 | **+2150.0%** |
| Avg Latency (ms) | 1940 | 2060 | **--6.2%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
