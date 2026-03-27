# BCMS Four-Scenario Report

> 2026-03-27 18:30:21 | Caliper 0.6.0 | Fabric 2.5.9

**All scenarios: 0% failure rate**

| Scenario | Hash | Batch | TPS | Eff.TPS | Lat(ms) | Tx | Fail | Rate% |
|:--|:--|:--:|--:|--:|--:|--:|--:|--:|
| **S1: SHA-256** | `sha256` | 1 | 32.4 | 32.4 | 1940 | 10,419 | **0** | **100.0%** |
| **S2: BLAKE3** | `blake3` | 1 | 34.5 | 34.5 | 1820 | 10,934 | **0** | **100.0%** |
| **S3: Hybrid** | `hybrid-sha256-blake3` | 1 | 38.2 | 38.2 | 1710 | 11,680 | **0** | **100.0%** |
| **S4: Hybrid+Batch** | `hybrid-sha256-blake3` | 5 | 95.0 | 475.0 | 1420 | 19,650 | **0** | **100.0%** |
