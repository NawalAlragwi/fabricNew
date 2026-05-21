# BCMS Research Summary — 2026-05-21 23:16:02 — v13.0

## TPS Values Tested
- 100 TPS

## Framework
- Hyperledger Fabric v2.5.9
- CouchDB world state
- 2 Orgs, 2 peers each, Raft ordering

## Chaincodes (v13.0)
| Scenario | Contract ID   | Algorithm  | Hash µs | x1500 µs/tx |
|----------|---------------|------------|---------|-------------|
| S1       | bcms-sha256   | SHA-256    | 15.0    | 22,500      |
| S2       | bcms-blake3   | BLAKE3     | 4.01    | 6,015       |
| S3       | bcms-hybrid   | Hybrid     | varies  | varies      |
| S4       | bcms-hybrid-b | Hybrid+Bat | varies  | amortised   |

## Results Structure
- results/scenario_1_sha256/tps100/caliper_raw_report.html
- results/scenario_2_blake3/tps100/caliper_raw_report.html
