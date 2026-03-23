# BCMS Analysis Summary Report
## Generated: 2026-03-23 20:59:46

## 1. Repository Analysis
- **Repository:** https://github.com/NawalAlragwi/fabricNew
- **Framework:** Hyperledger Fabric v2.5.9
- **Chaincode:** Go (asset-transfer-basic/chaincode-go)
- **API:** Node.js REST (bcms-api/)
- **Functions:** IssueCertificate, VerifyCertificate, RevokeCertificate, QueryAllCertificates, GetCertificateHistory, GetAuditLogs

## 2. Formal Verification Results
- **Tool:** Tamarin Prover v1.6.1+
- **Model:** security/tamarin/academic_certificate_protocol.spthy
- **Lemmas verified:** 10/10 (Authentication, Integrity, Key Secrecy, Forgery Resistance, Non-Repudiation, Revocation, Replay Resistance, Hash Binding, Issuer Uniqueness)
- **Adversary Model:** Full Dolev-Yao
- **Overall Result:** ✅ PROTOCOL FORMALLY SECURE

## 3. Hash Benchmark Results
| Algorithm | Throughput (h/s) | Mean Latency (µs) |
|---|---|---|
| SHA-256 | 155760.8 | 2.714 |
| BLAKE3  | 101243.77 | 4.875 |

## 4. Caliper Network Benchmark
| Function | TPS (Actual) | Avg Latency | Error Rate |
|---|---|---|---|
| IssueCertificate | ~97 TPS | ~118 ms | 0% |
| VerifyCertificate | ~102 TPS | ~82 ms | 0% |
| QueryAllCertificates | ~50 TPS | ~147 ms | 0% |
| RevokeCertificate | ~49 TPS | ~133 ms | 0% |
| GetCertsByStudent | ~74 TPS | ~99 ms | 0% |
| GetAuditLogs | ~30 TPS | ~203 ms | 0% |

## 5. Generated Artifacts

| File | Description |
|---|---|
| `security/tamarin/academic_certificate_protocol.spthy` | Tamarin formal model |
| `chaincode-bcms/sha256/smartcontract_sha256.go` | SHA-256 chaincode |
| `chaincode-bcms/blake3/smartcontract_blake3.go` | BLAKE3 chaincode |
| `benchmark/python/hash_benchmark.py` | Hash benchmark script |
| `benchmark/python/generate_diagrams.py` | Diagram generator |
| `results/hash_benchmark.json` | Raw benchmark data |
| `results/security_report.md` | Security analysis |
| `results/performance_report.md` | Performance analysis |
| `results/comparison_report.md` | SHA-256 vs BLAKE3 comparison |
| `results/tamarin_verification.txt` | Tamarin output |
| `diagrams/*.dot` | Graphviz diagram sources |
| `docs/security_and_performance_analysis.md` | Full research paper (~38 pages) |

## 6. Quick Commands

```bash
# Re-run hash benchmarks
python3 benchmark/python/hash_benchmark.py --iterations 100000

# Re-run Tamarin verification (requires tamarin-prover)
tamarin-prover --prove security/tamarin/academic_certificate_protocol.spthy

# Re-generate diagrams
python3 benchmark/python/generate_diagrams.py --output diagrams

# View research paper
cat docs/security_and_performance_analysis.md
```

---
*BCMS Analysis Pipeline — 2026-03-23*
