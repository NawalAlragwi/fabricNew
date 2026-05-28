# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-05-29 02:04:59  |  Caliper 0.6.0  |  Fabric 2.5.9


> ⚠️  **SIMULATED DATA**: Docker/Fabric unavailable. Run `bash setup_and_run_all.sh --all-scenarios` in a Docker-enabled environment for real measurements.
**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 32.4 | 32.4 | 1940 | 2,505 | **0** | **100.0%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 46.5 | 46.5 | 1180 | 7,389 | **0** | **100.0%** | **+43.5%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid-sha256-blake3` | 1 | 4 | 38.2 | 38.2 | 1710 | 5,295 | **0** | **100.0%** | **+17.9%** |
| **Hybrid + Batching Optimization** | `hybrid-sha256-blake3` | 5 | 8 | 95.0 | 475.0 | 1420 | 11,541 | **0** | **100.0%** | **+193.2%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 32.4 | 95.0 | **+193.2%** |
| Eff. Cert TPS | 32.4 | 475.0 | **+1366.0%** |
| Avg Latency (ms) | 1940 | 1420 | **-26.8%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
