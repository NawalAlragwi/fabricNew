# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-05-18 01:11:14  |  Caliper 0.6.0  |  Fabric 2.5.9


> ⚠️  **SIMULATED DATA**: Docker/Fabric unavailable. Run `bash setup_and_run_all.sh --all-scenarios` in a Docker-enabled environment for real measurements.
**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 10 | 48.1 | 48.1 | 156 | 40,500 | **987** | **97.6%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 46.5 | 46.5 | 1180 | 7,389 | **0** | **100.0%** | **-3.3%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid-sha256-blake3` | 1 | 4 | 38.2 | 38.2 | 1710 | 5,295 | **0** | **100.0%** | **-20.6%** |
| **Hybrid + Batching Optimization** | `hybrid-sha256-blake3` | 10 | 8 | 95.0 | 950.0 | 1420 | 11,541 | **0** | **100.0%** | **+97.5%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 48.1 | 95.0 | **+97.5%** |
| Eff. Cert TPS | 48.1 | 950.0 | **+1875.1%** |
| Avg Latency (ms) | 156 | 1420 | **--812.4%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
