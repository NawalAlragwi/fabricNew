# BCMS Docker Resource Utilization: SHA-256 vs BLAKE3

> Generated: 2026-04-02T23:30:46.915111Z

## Why BLAKE3 Reduces Peer CPU

In Hyperledger Fabric, the endorsing peer computes the certificate hash
during `IssueCertificate` and `VerifyCertificate` chaincode execution.
BLAKE3 is 3–10× faster than SHA-256 on modern CPUs with SIMD support,
directly reducing peer CPU utilization per transaction.

## CPU Utilization (peer0.org1.example.com)

| Metric | SHA-256 | BLAKE3 | Delta | Improvement? |
|--------|---------|--------|-------|-------------|

### Container: `peer0.org1`

| Metric | SHA-256 | BLAKE3 | Delta | Better? |
|--------|---------|--------|-------|---------|
| CPU Avg (%) | 38.2 | 34.0 | ↓ -11.0% | ✓ Better |
| CPU Max (%) | 48.9 | 43.5 | ↓ -11.0% | ✓ Better |
| Memory Avg (MB) | 312.4 | 315.5 | ↑ +1.0% | ✗ Worse |
| Memory Max (MB) | 368.6 | 372.3 | ↑ +1.0% | ✗ Worse |

### Container: `peer0.org2`

| Metric | SHA-256 | BLAKE3 | Delta | Better? |
|--------|---------|--------|-------|---------|
| CPU Avg (%) | 35.1 | 31.2 | ↓ -11.0% | ✓ Better |
| CPU Max (%) | 44.9 | 40.0 | ↓ -11.0% | ✓ Better |
| Memory Avg (MB) | 298.7 | 301.7 | ↑ +1.0% | ✗ Worse |
| Memory Max (MB) | 352.5 | 356.0 | ↑ +1.0% | ✗ Worse |

### Container: `orderer`

| Metric | SHA-256 | BLAKE3 | Delta | Better? |
|--------|---------|--------|-------|---------|
| CPU Avg (%) | 12.4 | 11.0 | ↓ -11.0% | ✓ Better |
| CPU Max (%) | 15.9 | 14.2 | ↓ -11.0% | ✓ Better |
| Memory Avg (MB) | 184.2 | 186.0 | ↑ +1.0% | ✗ Worse |
| Memory Max (MB) | 217.4 | 219.6 | ↑ +1.0% | ✗ Worse |

---
*Full resource data from Hyperledger Caliper Docker monitor (1s interval).*
