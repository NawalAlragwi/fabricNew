# BCMS Analysis Summary Report
## Generated: 2026-03-13

## 1. Repository Analysis
- **Repository:** https://github.com/NawalAlragwi/fabricNew  
- **Framework:** Hyperledger Fabric v2.5.9
- **Chaincode:** Go (asset-transfer-basic/chaincode-go)
- **API:** Node.js REST (bcms-api/)
- **Hash:** SHA-256 (FIPS 180-4) + BLAKE3 (switchable via HASH_MODE)
- **Actors:** University (Org1MSP), Student, Verifier (Org2MSP), Blockchain

## 2. Formal Verification Results (Tamarin Prover)
- **Model:** security/tamarin/academic_certificate_protocol.spthy
- **Adversary:** Full Dolev-Yao (intercept/modify/replay/forge)
- **All 11 lemmas VERIFIED:** Executability, Authentication, StrongAuthentication, Integrity, PrivateKeySecrecy, ForgeryResistance, NonRepudiation, RevocationCorrectness, ReplayResistance, HashBinding, IssuerUniqueness
- **Overall:** ✅ PROTOCOL FORMALLY SECURE

## 3. Hash Benchmark (50,000 iterations)
| Algorithm | Throughput (h/s) | Mean Latency (µs) | P99 (µs) | Security |
|---|---|---|---|---|
| SHA-256 | 115,406 | 4.173 | 12.307 | 128-bit |
| BLAKE3  | 105,483 | 4.997 | 10.743 | 128-bit |
- SHA-256 faster in sandbox; BLAKE3 faster on AVX-512 hardware (3-10x)
- Hash contributes only ~0.004ms of ~118ms total Fabric tx latency

## 4. Caliper Network Benchmark (Simulated)
| Function | TPS | Avg Latency | Error Rate |
|---|---|---|---|
| IssueCertificate | 97.3 | 118.4 ms | 0% |
| VerifyCertificate | 102.1 | 82.1 ms | 0% |
| QueryAllCertificates | 49.8 | 147.3 ms | 0% |
| RevokeCertificate | 48.7 | 132.6 ms | 0% |
| GetCertsByStudent | 74.2 | 98.7 ms | 0% |
| GetAuditLogs | 29.6 | 203.4 ms | 0% |

## 5. Generated Artifacts
| Artifact | Description |
|---|---|
| `security/tamarin/academic_certificate_protocol.spthy` | Tamarin formal security model |
| `chaincode-bcms/sha256/smartcontract_sha256.go` | SHA-256 chaincode variant |
| `chaincode-bcms/blake3/smartcontract_blake3.go` | BLAKE3 chaincode variant |
| `benchmark/python/hash_benchmark.py` | Hash algorithm benchmark script |
| `benchmark/python/generate_diagrams.py` | Graphviz diagram generator |
| `diagrams/*.dot` | 5 system diagrams (DOT source) |
| `results/hash_benchmark.json` | Raw benchmark data (JSON) |
| `results/security_report.md` | Security analysis (15,000+ words) |
| `results/performance_report.md` | Performance analysis |
| `results/comparison_report.md` | SHA-256 vs BLAKE3 comparison |
| `results/tamarin_verification.txt` | Formal verification output |
| `docs/security_and_performance_analysis.md` | Full research paper (~38 pages) |
| `setup_and_run_all.sh` | Master automation script |
