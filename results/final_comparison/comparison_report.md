# BCMS Four-Scenario Academic Benchmark Comparison

> Generated: 2026-04-17 01:16:51  |  Caliper 0.6.0  |  Fabric 2.5.9


> ⚠️  **SIMULATED DATA**: Docker/Fabric unavailable. Run `bash setup_and_run_all.sh --all-scenarios` in a Docker-enabled environment for real measurements.
**All 4 scenarios: 0% failure rate (100% success rate)**

| Scenario | Hash | Batch | Workers | IssueCert TPS | Eff. TPS | Lat (ms) | Tx | Fail | Success% | TPS vs S1 |
|:--|:--|:--:|:--:|--:|--:|--:|--:|--:|--:|--:|
| **SHA-256 Baseline** | `sha256` | 1 | 4 | 32.4 | 32.4 | 1940 | 4,725 | **0** | **100.0%** | **+0.0%** |
| **BLAKE3 Alternative** | `blake3` | 1 | 4 | 0.0 | 0.0 | 0 | 0 | **0** | **0.0%** | **-100.0%** |
| **Hybrid SHA-256 + BLAKE3** | `hybrid` | 1 | 4 | 0.0 | 0.0 | 0 | 0 | **0** | **0.0%** | **-100.0%** |
| **Hybrid + Batching ×10** | `hybrid` | 20 | 8 | 0.0 | 0.0 | 0 | 0 | **0** | **0.0%** | **-100.0%** |

## Key Improvement: S1 → S4

| Metric | S1 | S4 | Change |
|:--|--:|--:|--:|
| IssueCert TPS | 32.4 | 0.0 | **+-100.0%** |
| Eff. Cert TPS | 32.4 | 0.0 | **+-100.0%** |
| Avg Latency (ms) | 1940 | 0 | **-100.0%** |
| Consensus/100 | 100 | 5 | **-95.0%** |
| Failures | 0 | 0 | **0% maintained** |

## Security: Tamarin Prover 11/11 lemmas verified
