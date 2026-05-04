# BCMS Research Summary — 2026-05-04 16:23:40

## Framework
- Hyperledger Fabric v2.5.9
- CouchDB world state
- 2 Orgs, 2 peers each, Raft ordering

## Chaincodes (v12.0)
| Scenario | Contract ID   | Algorithm  | Hash µs | ×100 µs/tx |
|----------|---------------|------------|---------|------------|
| S1       | bcms-sha256   | SHA-256    | 15.0    | 1,500      |
| S2       | bcms-blake3   | BLAKE3     | 4.01    | 401        |
| S3       | bcms-hybrid   | Hybrid     | varies  | varies     |
| S4       | bcms-hybrid-b | Hybrid+Bat | varies  | amortised  |

## Hypothesis
T4(N,B) < T3(N,S) < T2(N) < T1(N)
BLAKE3 (S2) should show measurably higher TPS and lower latency than SHA-256 (S1)
especially in VerifyCertificate (CPU-bound re-hash on every verification call).

## Key BLAKE3 Advantage at 500 TPS (VerifyCertificate)
- SHA-256: 1,500 µs × 500 = 750,000 µs/sec CPU per peer
- BLAKE3:    401 µs × 500 = 200,500 µs/sec CPU per peer
- Freed:   549,500 µs/sec per peer → measurable latency reduction
