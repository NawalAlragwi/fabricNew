# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**BCMS (Blockchain Certificate Management System)** — a research project implementing tamper-proof academic certificate issuance and verification on Hyperledger Fabric v2.5. The research compares four cryptographic scenarios (SHA-256, BLAKE3, Hybrid, Hybrid-Batch) via Caliper benchmarking and Tamarin formal verification.

This repository is a fork of `hyperledger/fabric-samples` with BCMS-specific additions layered on top of the standard test-network scaffold.

---

## Prerequisites

- Docker v20.10+ with Docker Compose v2.0+
- Go v1.21+, Node.js v18+, npm v9+
- Hyperledger Fabric v2.5 binaries in `./bin/` (or on `$PATH`)
  ```bash
  curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.0 1.5.5
  export PATH=$PWD/bin:$PATH
  peer version  # should print 2.5.x
  ```

---

## Key Commands

### Full automated run (all 4 scenarios)
```bash
chmod +x setup_and_run_all.sh
./setup_and_run_all.sh --all-scenarios
```

Single scenario (1=SHA-256, 2=BLAKE3, 3=Hybrid, 4=Hybrid-Batch):
```bash
./setup_and_run_all.sh --scenario=1
```

Flags: `--skip-network`, `--skip-deploy`, `--skip-caliper`, `--skip-tamarin`, `--report-only`, `--comparison-only`, `--tps=50,100,200`

### Network management
```bash
cd test-network

# Start network with CouchDB + CA (required for BCMS)
./network.sh up createChannel -c mychannel -ca -s couchdb

# Deploy a chaincode variant (replace path for sha256/blake3/hybrid/hybrid-batch)
./network.sh deployCC -ccn basic -ccp ../chaincode-bcms/sha256 -ccl go \
    -c mychannel -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

# Tear down
./network.sh down
```

### Build/verify Go chaincodes
```bash
# Each variant is an independent Go module
cd chaincode-bcms/sha256  && go build ./...
cd chaincode-bcms/blake3  && go build ./...
cd chaincode-bcms/hybrid  && go build ./...
cd chaincode-bcms/hybrid-batch && go build ./...
```

### REST API
```bash
cd bcms-api
npm install
npm run enroll   # enroll admin identity (run once after network is up)
npm start        # production
npm run dev      # nodemon watch mode
```

### Caliper benchmarks
```bash
cd caliper-workspace
npm install
./fix_and_run_caliper.sh                       # default benchmark
# Scenario-specific configs:
npx caliper launch manager \
    --caliper-benchconfig benchmarks/benchConfig-S1-SHA256.yaml \
    --caliper-networkconfig networks/networkConfig.yaml
```

### Invoke chaincode directly (after sourcing org env)
```bash
cd test-network && source setOrgEnv.sh 1
export ORDERER_CA=$PWD/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
export PEER0_ORG1_CA=$PWD/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export PEER0_ORG2_CA=$PWD/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
    --tls --cafile "$ORDERER_CA" -C mychannel -n basic \
    --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" \
    --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" \
    -c '{"function":"InitLedger","Args":[]}' --waitForEvent
```

### Fix permissions (CI / cross-platform)
```bash
FIX_PERMISSIONS=true ./setup_and_run_all.sh
# or directly:
./scripts/fix-permissions.sh
```

---

## Architecture

### Four Chaincode Scenarios (Go)
Each lives in its own Go module under `chaincode-bcms/`:

| Directory | Scenario | Hash algorithm | Special feature |
|---|---|---|---|
| `sha256/` | S1 | `crypto/sha256` | Baseline |
| `blake3/` | S2 | `lukechampine.com/blake3` | Fast modern hash |
| `hybrid/chaincode/` | S3 | SHA-256 + BLAKE3 | Dual-hash per cert |
| `hybrid-batch/chaincode/` | S4 | SHA-256 + BLAKE3 | `IssueCertificateBatch` — atomic multi-cert tx |

All chaincodes implement the same interface: `InitLedger`, `IssueCertificate`, `VerifyCertificate`, `RevokeCertificate`, `QueryAllCertificates`, `GetCertificatesByStudent`, `GetAuditLogs`. S4 adds `IssueCertificateBatch`.

`Certificate` struct stores `transcript` (≈50 KB payload) on-ledger so `VerifyCertificate` hashes real data — this is intentional for fair benchmarking parity.

**RBAC**: `IssueCertificate` and `RevokeCertificate` require `Org1MSP`; `VerifyCertificate` and queries are open to any org.

### Network (test-network/)
- 2 organisations: `Org1MSP` (peer0.org1, port 7051) and `Org2MSP` (peer0.org2, port 9051)
- Single Raft orderer on port 7050
- CouchDB state databases (couchdb0 port 5984, couchdb1 port 7984) — required for `GetCertificatesByStudent` rich queries
- Channel: `mychannel`, chaincode name: `basic`
- Endorsement policy: `OR('Org1MSP.peer','Org2MSP.peer')`

CouchDB indexes live in each chaincode's `META-INF/statedb/couchdb/indexes/` and are deployed automatically with the chaincode.

### REST API (bcms-api/)
Node.js/Express app using `@hyperledger/fabric-gateway` v1.4. Exposes HTTP routes (see `src/routes/`) that delegate to Fabric gateway calls in `src/fabric/`. Prometheus metrics exposed for Grafana at `/metrics`. Logs via Winston to `logs/`.

### Caliper Benchmarking (caliper-workspace/)
Caliper 0.6.0. Workload scripts in `workload/` (one JS file per chaincode function). Benchmark configs in `benchmarks/` — separate YAML per scenario (`benchConfig-S1-SHA256.yaml` … `benchConfig-S4-HybridBatch.yaml`). Reports land in `results/` as HTML files and in `caliper-workspace/report*.html`.

`setup_and_run_all.sh` calls `wait_for_chaincode_image()` after every `deployCC` to force the peer to build the Docker chaincode image before Caliper starts (avoiding the "No such image: dev-peer0..." failure).

### Formal Verification (security/tamarin/)
`academic_certificate_protocol.spthy` — Tamarin prover model of the certificate protocol. Run via the `--skip-tamarin` flag omission; Tamarin must be installed separately.

### Report Generation (Python scripts)
Multiple `generate_*_report.py` scripts in root produce HTML comparison reports from `results/`. The master script calls the appropriate generator after each Caliper run.

---

## Important Invariants

- Always run `./network.sh down && docker volume prune && docker rmi $(docker images -q dev-peer*) 2>/dev/null` before bringing the network back up. This resets the chaincode sequence to 1 and prevents "sequence mismatch" errors across re-runs.
- Caliper must see the chaincode Docker image already built before it starts. `setup_and_run_all.sh` handles this; if running Caliper manually, invoke `InitLedger` or another function once first.
- All four chaincode variants use the same ledger key prefix `CERT_` in `InitLedger` seed data (range-query safe). CouchDB index selector includes `"issueDate":{"$gt":null}` — do not remove this.
- `IssueCertificate` is idempotent (returns the existing cert if called twice with the same ID) to prevent MVCC conflicts during high-concurrency Caliper runs.
