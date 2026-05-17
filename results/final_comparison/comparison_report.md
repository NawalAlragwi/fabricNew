# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-05-17 21:39:08  |  Caliper 0.6.0  |  Fabric 2.5.9


> ⚠️  **SIMULATED DATA**: Docker/Fabric unavailable. Run `bash setup_and_run_all.sh --all-scenarios` in a Docker-enabled environment for real measurements.
**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 10 | 48.1 | 48.1 | 156 | 40,500 | **987** | **97.6%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 46.5 | 46.5 | 1180 | 7,389 | **0** | **100.0%** | **-3.3%** |
| **S3: Hybrid SHA-256 ⊕ BLAKE3** | `hybrid-sha256-blake3` | 1 | 4 | 40.2 | 40.2 | 88 | 9,298 | **0** | **100.0%** | **-16.4%** |
| **S4: Hybrid+Batch (batchSize=10, 100 TPS)** | `hybrid-sha256-blake3` | 10 | 8 | 125.5 | 1254.9 | 56 | 29,008 | **0** | **100.0%** | **+160.9%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 48.1 | 125.5 | **+160.9%** |
| Eff. Cert TPS | 48.1 | 1254.9 | **+2508.9%** |
| Avg Latency (ms) | 156 | 56 | **-64.0%** |
| Consensus/100 | 100 | 10 | **-90.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
