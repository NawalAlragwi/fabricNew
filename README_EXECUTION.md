# BCMS BLAKE3 Migration — Execution Guide

> **Branch:** `fabric-blake3`  
> **Research Paper:** *"Enhancing Trust and Transparency in Education Using Blockchain: A Hyperledger Fabric-Based Framework"*  
> **Migration:** SHA-256 → BLAKE3 (`github.com/zeebo/blake3`)  
> **Date:** 2026-04-02

---

## Table of Contents

1. [Overview](#1-overview)
2. [Code Changes Summary](#2-code-changes-summary)
3. [Quick Start](#3-quick-start)
4. [Step-by-Step Execution](#4-step-by-step-execution)
5. [Benchmark Configuration](#5-benchmark-configuration)
6. [Interpreting BLAKE3 Performance Results](#6-interpreting-blake3-performance-results)
7. [On-Chain Integrity Verification](#7-on-chain-integrity-verification)
8. [Python Analysis Script](#8-python-analysis-script)
9. [Troubleshooting](#9-troubleshooting)
10. [File Structure](#10-file-structure)

---

## 1. Overview

This branch implements a complete structural migration of the **BCMS chaincode** from SHA-256 to **BLAKE3**, enabling a scientifically rigorous performance comparison on Hyperledger Fabric v2.5.

### Why BLAKE3?

| Property | SHA-256 (`crypto/sha256`) | BLAKE3 (`github.com/zeebo/blake3`) |
|----------|--------------------------|-------------------------------------|
| Output size | 256 bits | 256 bits |
| Security level | 128-bit collision | 128-bit collision |
| Algorithm | Merkle–Damgård | Tree-based Merkle |
| SIMD support | Partial | AVX-512, AVX2, NEON |
| Throughput (software) | ~250–350 MB/s | ~800–3,000 MB/s |
| Go package | Standard library | `github.com/zeebo/blake3` v0.2.4 |
| npm package | `crypto` (built-in) | `blake3` npm package |

### Research Hypothesis

> BLAKE3's 3–10× faster hash computation will reduce peer CPU utilization during  
> `IssueCertificate` endorsement, yielding higher sustainable TPS and lower latency  
> at identical workload settings compared to the SHA-256 baseline.

---

## 2. Code Changes Summary

### 2.1 Chaincode (Go) — `chaincode-bcms/blake3/`

**File:** `smartcontract_blake3.go`

| Change | SHA-256 Baseline | BLAKE3 Migration |
|--------|-----------------|-----------------|
| Import | `"crypto/sha256"` | `"github.com/zeebo/blake3"` |
| Hash function | `sha256.Sum256([]byte(data))` | `blake3.Sum256([]byte(data))` |
| Hash constant | `"sha256"` | `"BLAKE3"` |
| Certificate field | `HashAlgo: "sha256"` | `HashAlgorithm: "BLAKE3"` *(new explicit on-chain tag)* |
| Audit logging | Disabled (benchmark mode) | **Kept disabled** (benchmark mode) |
| ID prefix | `CERT_` | `CERT_B3_` *(BLAKE3 identifier)* |

**Key code change in `ComputeCertHashBLAKE3()`:**

```go
// SHA-256 (baseline):
hash := sha256.Sum256([]byte(data))
return fmt.Sprintf("%x", hash)

// BLAKE3 (migration):
hashBytes := blake3.Sum256([]byte(data))
return fmt.Sprintf("%x", hashBytes[:])
```

**Schema update — on-chain auditability:**

```go
// Certificate struct — new HashAlgorithm field:
type Certificate struct {
    ...
    HashAlgorithm string `json:"HashAlgorithm"` // "BLAKE3" — explicit on-chain audit tag
    HashAlgo      string `json:"HashAlgo"`      // legacy alias preserved for compatibility
    ...
}
```

**`go.mod` dependency change:**

```diff
- // No external hash library
+ github.com/zeebo/blake3 v0.2.4
```

> **Note on library choice:** The chaincode uses `github.com/zeebo/blake3` (a pure-Go, CGO-free implementation). An alternative is `lukechampine.com/blake3`. The `zeebo/blake3` variant was chosen for:
> - CGO-free compilation (no C toolchain required in chaincode Docker image)
> - Explicit 256-bit API: `blake3.Sum256(data)`
> - Compatible with Hyperledger Fabric's chaincode build environment

### 2.2 Client-Side Workload (Node.js) — `caliper-workspace/workload/`

All 6 workload files have been updated:

| File | Change |
|------|--------|
| `issueCertificate.js` | Replaced `crypto.createHash('sha256')` with `blake3.hash()` |
| `verifyCertificate.js` | Same BLAKE3 hash recomputation for on-chain hash-match |
| `revokeCertificate.js` | Updated ID prefix to `CERT_B3_` |
| `queryAllCertificates.js` | No hash change (pure CouchDB query) |
| `getCertificatesByStudent.js` | No hash change (pure CouchDB query) |
| `getAuditLogs.js` | No hash change (returns empty array) |

**Key hash migration in `issueCertificate.js`:**

```javascript
// SHA-256 (baseline):
const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
const certHash = crypto.createHash('sha256').update(fields).digest('hex');

// BLAKE3 (migration):
const b3 = require('blake3');
const data = [studentID, studentName, degree, issuer, issueDate].join('|');
const hashBytes = b3.hash(Buffer.from(data, 'utf8'));
const certHash  = Buffer.from(hashBytes).toString('hex');
```

**ID pattern change:**

```javascript
// SHA-256: CERT_{workerIndex}_{txIndex}
// BLAKE3:  CERT_B3_{workerIndex}_{txIndex}
const certID = `CERT_B3_${w}_${this.txIndex}`;
```

**`package.json` dependency added:**

```json
{
  "dependencies": {
    "@hyperledger/caliper-cli": "0.6.0",
    "blake3": "^0.3.3",
    "fabric-network": "^2.2.19"
  }
}
```

### 2.3 Benchmark Configuration — `caliper-workspace/benchmarks/benchConfig.yaml`

| Setting | Value | Note |
|---------|-------|------|
| Test name | `bcms-blake3-certificate-benchmark` | Updated label |
| Hash mode | BLAKE3 | Updated description |
| TPS (Round 1 Issue) | **50 TPS** | **Identical to SHA-256 baseline** |
| TPS (Round 2 Verify) | **100 TPS** | **Identical to SHA-256 baseline** |
| TPS (Round 3 Query) | **50 TPS** | **Identical to SHA-256 baseline** |
| TPS (Round 4 Revoke) | **50 TPS** | **Identical to SHA-256 baseline** |
| TPS (Round 5 Student) | **75 TPS** | **Identical to SHA-256 baseline** |
| TPS (Round 6 Audit) | **30 TPS** | **Identical to SHA-256 baseline** |
| Total transactions | 14,550 | Same as baseline |
| Workers | 8 | Same as baseline |

> **Critical scientific validity:** All TPS settings are **identical** to the SHA-256 baseline.  
> Only the hash algorithm changes. This ensures a true "apples-to-apples" comparison.

### 2.4 Automation Script — `setup_and_run_all.sh`

| Change | Description |
|--------|-------------|
| Network teardown | Added explicit `docker volume prune` and network cleanup |
| Chaincode path | `chaincode-bcms/blake3` (was `asset-transfer-basic/chaincode-go`) |
| Go dependency | `go mod tidy && go build ./...` for BLAKE3 before deploy |
| npm install | Installs `blake3` package in caliper-workspace |
| Report export | Results copied to `results/blake3/` with metadata JSON |
| Analysis | Runs `results/analyze_results.py` after benchmark |

---

## 3. Quick Start

```bash
# 1. Clone and switch to the research branch
git clone <repo-url>
cd fabricNew
git checkout fabric-blake3

# 2. Verify branch
git branch
# * fabric-blake3

# 3. Run the full benchmark (requires Docker + Go + Node.js)
bash setup_and_run_all.sh

# 4. View results
ls results/blake3/
cat results/blake3/comparison_sha256_vs_blake3.md

# 5. Run analysis only (no network needed)
python3 results/analyze_results.py --synthetic
```

---

## 4. Step-by-Step Execution

### Prerequisites

```bash
# Verify Docker
docker --version        # Docker 20.10+
docker compose version  # Docker Compose 2.x

# Verify Go
go version              # go1.21+ required for github.com/zeebo/blake3

# Verify Node.js
node --version          # v16+ required for blake3 WASM support
npm --version           # 8+

# Verify Python
python3 --version       # 3.8+
```

### Step 1: Start Fabric Network

```bash
cd test-network
./network.sh down                                          # clean teardown
./network.sh up createChannel -c mychannel -ca -s couchdb  # start with CouchDB
sleep 30                                                    # wait for stabilization
cd ..
```

### Step 2: Download BLAKE3 Dependency

```bash
cd chaincode-bcms/blake3
export GOFLAGS="-mod=mod"
export GOPROXY="https://proxy.golang.org,direct"
go mod download
go mod tidy
go build ./...              # verify compilation
cd ../..
```

### Step 3: Deploy BLAKE3 Chaincode

```bash
export PATH="${PWD}/bin:$PATH"
export FABRIC_CFG_PATH="${PWD}/config/"

cd test-network
./network.sh deployCC \
    -ccn basic \
    -ccp ../chaincode-bcms/blake3 \
    -ccl go \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"
sleep 15                    # wait for chaincode container
cd ..
```

### Step 4: Install blake3 npm Package

```bash
cd caliper-workspace
rm -rf node_modules package-lock.json
npm install                 # installs blake3 npm package
npx caliper bind --caliper-bind-sut fabric:2.5 --caliper-bind-args=-g
cd ..
```

### Step 5: Run Caliper Benchmark (6 Rounds)

```bash
cd caliper-workspace

# Generate network config (or use the setup_and_run_all.sh script)
# ... (see setup_and_run_all.sh for full network config generation)

npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

cd ..
```

### Step 6: Export Results

```bash
mkdir -p results/blake3
cp caliper-workspace/report.html results/blake3/report_blake3.html
```

### Step 7: Run Analysis

```bash
# With real results:
python3 results/analyze_results.py \
    --sha256-json results/scenario_1_sha256/caliper_results.json \
    --blake3-json results/blake3/caliper_results.json \
    --output-dir  results/blake3

# With synthetic demo data (no real benchmark needed):
python3 results/analyze_results.py --synthetic
```

---

## 5. Benchmark Configuration

### TPS Configuration (Apples-to-Apples Comparison)

```
Round 1: IssueCertificate     —  50 TPS × 30s =  1,500 transactions [BLAKE3 write]
Round 2: VerifyCertificate    — 100 TPS × 30s =  3,000 transactions [BLAKE3 read]
Round 3: QueryAllCertificates —  50 TPS × 30s =  1,500 transactions [CouchDB query]
Round 4: RevokeCertificate    —  50 TPS × 30s =  1,500 transactions [revocation write]
Round 5: GetCertsByStudent    —  75 TPS × 30s =  2,250 transactions [student query]
Round 6: GetAuditLogs         —  30 TPS × 30s =    900 transactions [audit query]
──────────────────────────────────────────────────────────────────────────────────
TOTAL                                            14,550 transactions
```

### Success Criteria

| Criterion | Target |
|-----------|--------|
| Fail rate | **0.00%** across all 14,550 transactions |
| Resource data | Full Docker monitor CPU/RAM for peer0.org1, peer0.org2, orderer |
| On-chain integrity | `HashAlgorithm: "BLAKE3"` in every issued certificate |
| Report format | HTML (Caliper) + JSON (parsed) + CSV/MD (comparison) |

---

## 6. Interpreting BLAKE3 Performance Results

### Expected Metrics

| Round | Expected BLAKE3 vs SHA-256 | Reason |
|-------|---------------------------|--------|
| `IssueCertificate` | +15–25% TPS, -15–20% latency | BLAKE3 hash 3–10× faster → lower peer CPU |
| `VerifyCertificate` | +8–12% TPS, -8–12% latency | Faster client-side hash recompute |
| `QueryAllCertificates` | ≈ same (±3%) | Pure I/O — no hash overhead |
| `RevokeCertificate` | +5–10% TPS | No hash in revoke path; MVCC benefit |
| `GetCertsByStudent` | ≈ same (±4%) | Pure CouchDB query |
| `GetAuditLogs` | ≈ same (±2%) | Returns empty array |

### Reading the HTML Report

The Caliper HTML report (at `caliper-workspace/report.html`) shows:

1. **Throughput chart** — TPS over time per round. Look for a BLAKE3 IssueCertificate
   plateau that is higher than the SHA-256 baseline plateau.

2. **Latency chart** — Average/p50/p95/p99 latency. BLAKE3 should show lower values
   on write rounds.

3. **Resource monitor tables** — CPU % and RAM for each Docker container. BLAKE3
   should show lower peer CPU on `peer0.org1.example.com`.

4. **Transaction counts** — Verify `Fail: 0` for all rounds.

### Reading the Comparison Markdown

```bash
cat results/blake3/comparison_sha256_vs_blake3.md
```

Key sections:
- **Throughput Comparison** — TPS delta with `↑` (better) or `↓` (worse) arrows
- **Latency Comparison** — Latency delta (lower is better → `↓` is improvement)
- **Resource Utilization** — CPU/RAM delta per Docker container
- **Transaction Counts** — Verify 0 failures

### Understanding the Factor Column

The `Factor ×` column in comparison tables shows the BLAKE3/SHA-256 ratio:

```
Factor = BLAKE3_TPS / SHA256_TPS

Factor > 1.0 → BLAKE3 is faster (good)
Factor < 1.0 → BLAKE3 is slower (unexpected — investigate)
Factor = 1.0 → identical performance
```

A BLAKE3 IssueCertificate factor of `1.22` means **BLAKE3 achieved 22% more transactions per second** at the same TPS target setting.

---

## 7. On-Chain Integrity Verification

### Verify BLAKE3 Tag in Certificates

After running the benchmark, verify that certificates on-chain have the BLAKE3 tag:

```bash
export PATH="${PWD}/bin:$PATH"
export FABRIC_CFG_PATH="${PWD}/config/"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${PWD}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS="localhost:7051"

# Query a certificate issued by BLAKE3 benchmark
peer chaincode query \
    -C mychannel \
    -n basic \
    -c '{"Args":["QueryAllCertificates"]}'
```

**Expected output** — each certificate should have:
```json
{
  "HashAlgorithm": "BLAKE3",
  "HashAlgo": "BLAKE3",
  "ID": "CERT_B3_0_1",
  "CertHash": "<64-char BLAKE3 hex hash>",
  ...
}
```

### Verify Hash Consistency

The BLAKE3 hash stored on-chain must match the client-side computation:

```javascript
// In Node.js REPL:
const blake3 = require('blake3');
const studentID   = 'STU_0_1';
const studentName = 'Student_0_1';
const degree      = 'Bachelor of Computer Science';
const issuer      = 'Digital University';
const issueDate   = '2026-04-02';

const data = [studentID, studentName, degree, issuer, issueDate].join('|');
const hash = Buffer.from(blake3.hash(Buffer.from(data, 'utf8'))).toString('hex');
console.log(hash);  // Must match CertHash on ledger
```

```bash
# In Go (verify chaincode hash matches):
cd chaincode-bcms/blake3
cat > /tmp/verify_hash.go << 'EOF'
package main

import (
    "fmt"
    "strings"
    "github.com/zeebo/blake3"
)

func main() {
    data := strings.Join([]string{"STU_0_1", "Student_0_1", "Bachelor of Computer Science", "Digital University", "2026-04-02"}, "|")
    hash := blake3.Sum256([]byte(data))
    fmt.Printf("BLAKE3: %x\n", hash[:])
}
EOF
go run /tmp/verify_hash.go
```

Both Node.js and Go outputs **must be identical** for hash-match verification to pass.

---

## 8. Python Analysis Script

### Usage

```bash
# Default run (uses results/scenario_1_sha256/ and results/blake3/)
python3 results/analyze_results.py

# Explicit paths
python3 results/analyze_results.py \
    --sha256-json results/scenario_1_sha256/caliper_results.json \
    --blake3-json results/blake3/caliper_results.json \
    --output-dir  results/blake3

# Synthetic demo (no actual benchmark data needed)
python3 results/analyze_results.py --synthetic
```

### Output Files

| File | Format | Contents |
|------|--------|---------|
| `comparison_sha256_vs_blake3.csv` | CSV | Machine-readable comparison table |
| `comparison_sha256_vs_blake3.md` | Markdown | Research-ready comparison tables |
| `performance_improvement.json` | JSON | Structured delta summary |
| `resource_comparison.md` | Markdown | Docker CPU/RAM comparison |

### Input Format (caliper_results.json)

The script expects Caliper results in this format:

```json
{
    "scenario": 1,
    "title": "SHA-256 Baseline",
    "timestamp": "2026-04-02T00:00:00Z",
    "framework": "Hyperledger Fabric v2.5",
    "caliper_version": "0.6.0",
    "chaincode": "chaincode-bcms/sha256",
    "hash_algorithm": "sha256",
    "workers": 8,
    "resource_metrics": {
        "peer0.org1.example.com": {
            "cpu_pct_avg": 38.2,
            "cpu_pct_max": 48.9,
            "mem_mb_avg": 312.4,
            "mem_mb_max": 368.6
        }
    },
    "rounds": [
        {
            "label": "IssueCertificate",
            "tps": 32.4,
            "avg_latency_ms": 1940.0,
            "p95_s": 3.12,
            "p99_s": 4.20,
            "succ": 972,
            "fail": 0,
            "success_rate_pct": 100.0
        }
    ]
}
```

---

## 9. Troubleshooting

### Issue: `blake3` npm package not found

```
Error: Cannot find module 'blake3'
```

**Fix:**
```bash
cd caliper-workspace
npm install blake3
# Verify installation:
node -e "const b3 = require('blake3'); console.log('blake3 OK');"
```

### Issue: Go build fails for BLAKE3 chaincode

```
cannot find module github.com/zeebo/blake3
```

**Fix:**
```bash
cd chaincode-bcms/blake3
export GOFLAGS="-mod=mod"
export GOPROXY="https://proxy.golang.org,direct"
go mod download
go mod tidy
go build ./...
```

### Issue: Hash mismatch (VerifyCertificate returns hashMatch: false)

**Cause:** Client JS and chaincode Go use different data formats or different libraries.

**Fix:** Verify the concatenation formula is identical:
```
Go:    strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")
JS:    [studentID, studentName, degree, issuer, issueDate].join('|')
```

Both must produce the same input to BLAKE3. The output must be identical hex strings.

### Issue: MVCC conflicts (transactions failing)

**Cause:** Workers using the same certificate IDs.

**Verify:** The `CERT_B3_{workerIndex}_{txIndex}` pattern ensures unique IDs per worker.
No two workers share an ID, so MVCC conflicts are impossible.

### Issue: `docker ps` shows no containers

**Fix:**
```bash
cd test-network
./network.sh down
./network.sh up createChannel -c mychannel -ca -s couchdb
sleep 30
# Redeploy chaincode:
./network.sh deployCC -ccn basic -ccp ../chaincode-bcms/blake3 -ccl go \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"
```

### Issue: report.html not generated

**Check:**
```bash
# 1. Verify Docker containers are running:
docker ps | grep -E "peer|orderer|couchdb"

# 2. Verify chaincode is deployed:
peer chaincode list --installed
peer chaincode list --instantiated -C mychannel

# 3. Check Caliper log:
cat caliper-workspace/caliper.log | tail -50

# 4. Verify blake3 npm is installed:
ls caliper-workspace/node_modules/blake3/
```

---

## 10. File Structure

```
fabric-blake3/
├── chaincode-bcms/
│   └── blake3/
│       ├── smartcontract_blake3.go    ← BLAKE3 chaincode (zeebo/blake3)
│       ├── main.go                    ← Chaincode entry point
│       └── go.mod                     ← Includes github.com/zeebo/blake3
│
├── caliper-workspace/
│   ├── benchmarks/
│   │   └── benchConfig.yaml           ← BLAKE3 benchmark (same TPS as baseline)
│   ├── workload/
│   │   ├── issueCertificate.js        ← BLAKE3 client hash (blake3 npm)
│   │   ├── verifyCertificate.js       ← BLAKE3 hash recompute
│   │   ├── revokeCertificate.js       ← CERT_B3_ ID pattern
│   │   ├── queryAllCertificates.js    ← No hash (pure CouchDB query)
│   │   ├── getCertificatesByStudent.js ← No hash (pure CouchDB query)
│   │   └── getAuditLogs.js            ← No hash (returns [])
│   └── package.json                   ← blake3 npm dependency added
│
├── results/
│   ├── analyze_results.py             ← SHA-256 vs BLAKE3 comparison script
│   ├── scenario_1_sha256/             ← SHA-256 baseline (from fabric-baseline)
│   │   └── caliper_results.json
│   └── blake3/                        ← BLAKE3 results (generated by benchmark)
│       ├── report_blake3.html         ← Caliper HTML report (generated)
│       ├── caliper_results.json       ← Parsed metrics (generated)
│       ├── benchmark_meta.json        ← Run metadata (generated)
│       ├── comparison_sha256_vs_blake3.csv  ← Analysis CSV (generated)
│       ├── comparison_sha256_vs_blake3.md   ← Analysis Markdown (generated)
│       ├── performance_improvement.json     ← Delta summary (generated)
│       └── resource_comparison.md          ← Docker CPU/RAM comparison (generated)
│
├── setup_and_run_all.sh               ← Updated automation script (BLAKE3 mode)
└── README_EXECUTION.md                ← This file

```

---

## Key Architectural Decisions

### 1. Pure-Go BLAKE3 (CGO-free)

`github.com/zeebo/blake3` was chosen over alternatives because:
- **CGO-free**: Fabric chaincode containers don't have a C compiler
- **Pure Go**: Works in restricted Docker build environments
- **API match**: `blake3.Sum256(data)` → identical interface to `sha256.Sum256(data)`

### 2. `CERT_B3_` ID Prefix

The `CERT_B3_` prefix on benchmark certificate IDs serves three purposes:
1. **Namespace separation**: BLAKE3 certs don't collide with baseline `CERT_` keys
2. **On-chain identification**: Ledger queries can filter by algorithm via ID prefix
3. **Reproducibility**: Re-running the benchmark creates the same key space

### 3. Audit Logging Disabled

Audit logging is intentionally disabled in benchmark mode for both SHA-256 and BLAKE3:
- Audit log writes create additional MVCC pressure on `AUDIT_*` keys
- Disabling ensures the TPS measurement reflects *only* hash algorithm overhead
- This matches the SHA-256 baseline configuration for valid comparison
- Enable with `AUDIT_LOG_ENABLED=true` in production deployments

### 4. Identical TPS Settings

All six rounds use the **same TPS targets** as the SHA-256 baseline:

```
50 / 100 / 50 / 50 / 75 / 30 TPS
```

This is the most scientifically rigorous approach: when TPS settings differ, any throughput improvement could be attributed to the rate controller rather than the hash algorithm. By keeping TPS identical, we measure **actual system capacity** rather than configured rate.

---

*Branch: `fabric-blake3` | Research Paper: Hyperledger Fabric BCMS | Author: Research Team*
