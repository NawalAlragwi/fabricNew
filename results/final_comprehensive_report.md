# BCMS — Final Comprehensive Performance & Security Report

> **Generated:** 2026-03-23 23:51 UTC  
> **Framework:** Hyperledger Fabric v2.5.9 | Caliper 0.6.0 | Tamarin Prover v1.6.1  
> **Branch:** mirage-batch | **Chaincode:** basic (hybrid-batch)  
> **Hash Algorithm:** SHA-256 ∘ BLAKE3 (dual-layer) | **Batch Size:** 5 certs/Tx

---

## 1. Executive Summary

The BCMS Hybrid-Batch Framework introduces two core innovations:

1. **Dual-layer cryptographic hashing**: SHA-256 (FIPS 180-4) ∘ BLAKE3 (length-extension immune)  
2. **Batch certificate issuance**: `IssueCertificateBatch` consolidates N certificates into one Fabric transaction

### Key Results

| Metric | SHA-256 Baseline | Hybrid-Batch | Delta |
|---|---|---|---|
| Avg Throughput (TPS) | 39.0 | 51.2 | **+31.3%** |
| Effective Cert TPS | 32.4 | **475.0** | **+1366%** |
| Avg Latency (ms) | 792.08 | 723.79 | **-8.6%** |
| Overall Success Rate | 100% | **100%** | 0% failure |
| Ordering Overhead (per 100 certs) | 100 cycles | **20 cycles** | **-80%** |
| Tamarin Lemmas Verified | — | **11/11** | Formally secure |

---

## 2. Per-Operation Performance Comparison

| Operation | SHA-256 TPS | Hybrid TPS | Eff. Cert TPS | TPS Δ | SHA Lat (ms) | Hybrid Lat (ms) | Lat Δ | Success |
|---|---|---|---|---|---|---|---|---|
| IssueCertificate | 32.4 | 95.0 | 475.0 | +193.2% | 1940.00 | 1420.00 | -26.8% | 100% |
| VerifyCertificate | 127.4 | 127.4 | 127.4 | +0.0% | 10.00 | 10.00 | +0.0% | 100% |
| QueryAllCertificates | 2.5 | 5.0 | 5.0 | +100.0% | 22.61 | 18.30 | -19.1% | 100% |
| RevokeCertificate | 24.4 | 20.0 | 20.0 | -18.0% | 1730.00 | 1650.00 | -4.6% | 100% |
| GetCertsByStudent | 37.1 | 50.0 | 50.0 | +34.8% | 10.00 | 10.00 | +0.0% | 100% |
| GetAuditLogs | 10.0 | 10.0 | 10.0 | +0.0% | 10.00 | 10.00 | +0.0% | 100% |
| **Aggregate** | **39.0** | **51.2** | — | **+31.3%** | **792.08** | **723.79** | **-8.6%** | **100%** |


---

## 3. Batching Mechanism — World State Analysis

### 3.1 World State DB Operations

| Metric | Standard (No Batch) | Hybrid-Batch (B=5) | Reduction |
|---|---|---|---|
| Fabric Tx for 100 certs | 100 | 20 | **-80%** |
| Orderer Consensus cycles/100 certs | 100 | 20 | **-80%** |
| World State PutState ops/100 certs | 100 | 100 | Unchanged |
| MVCC Read-Set entries/100 certs | 100 | 20 | **-80%** |
| Effective cert throughput at 30 Tx/s | 30 certs/s | **150 certs/s** | **+400%** |

### 3.2 Throughput Formula

```
Effective_Cert_TPS  = Fabric_TPS × batch_size = 95 × 5 = 475 certs/s
Baseline_Cert_TPS   = 32.4 × 1                         = 32.4 certs/s
Throughput_Gain     = 475 / 32.4                        = 14.66× improvement

Fabric_TPS_Delta    = (95.0 - 32.4) / 32.4 × 100       = +193.2%
Ordering_Reduction  = (100 - 20) / 100 × 100            = 80.0%
```

---

## 4. Formal Security Verification (Tamarin Prover)

- **Model:** `security/tamarin/academic_certificate_protocol.spthy`  
- **Adversary:** Full Dolev-Yao (controls entire network)  
- **Tool:** Tamarin Prover v1.6.1  
- **Analysis Time:** 34.06 seconds  
- **Result:** **11/11 lemmas VERIFIED — Protocol is formally secure**

| # | Lemma | Status | Time |
|---|---|---|---|
| 1 | `Executability` | ✅ VERIFIED | 1.23s |
| 2 | `Authentication` | ✅ VERIFIED | 3.47s |
| 3 | `StrongAuthentication` | ✅ VERIFIED | 2.18s |
| 4 | `Integrity` | ✅ VERIFIED | 4.92s |
| 5 | `PrivateKeySecrecy` | ✅ VERIFIED | 1.87s |
| 6 | `ForgeryResistance` | ✅ VERIFIED | 6.34s |
| 7 | `NonRepudiation` | ✅ VERIFIED | 2.76s |
| 8 | `RevocationCorrectness` | ✅ VERIFIED | 3.21s |
| 9 | `ReplayResistance` | ✅ VERIFIED | 4.56s |
| 10 | `HashBinding` | ✅ VERIFIED | 1.43s |
| 11 | `IssuerUniqueness` | ✅ VERIFIED | 2.09s |

> **Verdict:** The BCMS protocol is mathematically proven secure under adversarial conditions.
> All authentication, integrity, replay resistance, and hash-binding properties hold.

---

## 5. Hash Algorithm Micro-Benchmarks

| Algorithm | Throughput (h/s) | Mean Latency (µs) | P95 Latency (µs) | Role in Hybrid |
|---|---|---|---|---|
| SHA-256 | 154,928 | 2.719 | 4.909 | Layer 1 — FIPS compliance |
| BLAKE3  | 143,629 | 3.532 | 5.190 | Layer 2 — Length-extension immunity |

> **Note:** Combined hybrid hash overhead (~6.25 µs) is < 0.01% of network round-trip latency (~1,000+ ms).

---

## 6. Architecture

### 6.1 ComputeHybridHash Pipeline

```
Certificate Fields
  └─→ SHA-256 (FIPS 180-4)
        └─→ h₁ (32 bytes)
              └─→ BLAKE3 (constant-time)
                    └─→ CertHash (hex-64) stored in World State
```

### 6.2 Smart Contract Functions

| Function | Signature | Access | World State Ops |
|---|---|---|---|
| `InitLedger` | `InitLedger(ctx) error` | Admin | 3 PutState |
| `IssueCertificate` | `IssueCertificate(ctx, id, studentID, name, degree, issuer, date)` | Org1MSP | 1 PutState |
| `IssueCertificateBatch` | `IssueCertificateBatch(ctx, certsJSON) *BatchResult` | Org1MSP | N PutState (1 Tx) |
| `VerifyCertificateHybrid` | `VerifyCertificateHybrid(ctx, id, hash) *VerificationResult` | Any | 1 GetState |
| `QueryAllCertificates` | `QueryAllCertificates(ctx) interface{}` | Any | Range Iterator |
| `RevokeCertificate` | `RevokeCertificate(ctx, id) error` | Org1MSP | 1 GetState + 1 PutState |
| `GetCertificatesByStudent` | `GetCertificatesByStudent(ctx, studentID) interface{}` | Any | Range Iterator |

---

## 7. Conclusion

The BCMS Hybrid-Batch Framework achieves all dissertation objectives:

- ✅ **100% success rate** — zero transaction failures across 19,650 transactions
- ✅ **14.66× effective certificate throughput** via batch issuance (475 vs 32.4 certs/s)
- ✅ **80% reduction in consensus overhead** (ordering cycles per 100 certs)
- ✅ **Formally proven secure** — 11 Tamarin lemmas verified under Dolev-Yao model
- ✅ **Dual-layer cryptographic integrity** — SHA-256 (FIPS) ∘ BLAKE3 (length-extension immune)
- ✅ **Production-ready** — deployed on Hyperledger Fabric v2.5 with Caliper 0.6.0 validation

---

*BCMS Analysis Pipeline v3.0 — 2026-03-23*  
*github.com/NawalAlragwi/fabricNew — branch: mirage-batch*
