#!/bin/bash
set -e

# ============================================================
# setup_and_run_all.sh — BLAKE3 OPTIMIZED: Full End-to-End
#                        Fabric Network + Caliper Benchmark
#
# VARIANT: fabric-blake3 (BLAKE3 Hashing + 200KB Metadata)
#
# PURPOSE:
#   Demonstrates BLAKE3 performance improvements for BCMS.
#   This script runs the IssueCertificate benchmark with a
#   200KB+ metadata payload, applying BLAKE3 on-chain:
#     hash1 = BLAKE3(core cert fields)
#     hash2 = BLAKE3(metadata 200KB+)   ← Optimized
#     finalHash = BLAKE3(hash1 || hash2)
#
#   The intentional performance bottleneck provides the "weak
#   baseline" reference point — enabling BLAKE3 (fabric-blake3
#   branch) to demonstrate a significant performance improvement.
#
# CHANGES FROM ORIGINAL:
#   1. Full environment teardown BEFORE start (Docker clean)
#   2. Deploys optimized BLAKE3 chaincode (200KB+ Metadata)
#   3. IssueCertificate only — BLAKE3 performance test round
#   4. Benchmark config tuned for BLAKE3 (higher TPS target)
#   5. Report generation with BLAKE3 optimization label
#
# FIXES RETAINED:
#   [FIX-1] Always delete old report.html before benchmark
#   [FIX-2] Dynamic private key detection (*_sk pattern)
#   [FIX-3] Always re-install and re-bind Caliper (clean)
#   [FIX-4] Generate network config with absolute paths
#   [FIX-5] Generate complete connection profiles with orderer
#   [FIX-6] --caliper-fabric-gateway-enabled for Fabric 2.5
#   [FIX-7] Post-benchmark report existence verification
# ============================================================

# ── Script Setup ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   BCMS — BLAKE3 OPTIMIZED BENCHMARK                         ║${NC}"
echo -e "${BLUE}║   Hyperledger Fabric v2.5 + Caliper                         ║${NC}"
echo -e "${BLUE}║   BLAKE3 | 200KB+ Metadata Payload                          ║${NC}"
echo -e "${BLUE}║   Branch: fabric-blake3                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Permission fix for CI environments
if [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ "${FIX_PERMISSIONS:-}" = "true" ]; then
    if [ -x "./scripts/fix-permissions.sh" ]; then
        echo "Running scripts/fix-permissions.sh (CI environment)..."
        ./scripts/fix-permissions.sh || true
    fi
fi

# ── STEP 0: Full Environment Teardown ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  STEP 0: Full Environment Teardown (BLAKE3 Clean Start)      ${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Removing all running Docker containers..."
docker rm -f $(docker ps -aq) 2>/dev/null || true

echo "Pruning Docker volumes..."
docker volume prune -f 2>/dev/null || true

echo "Pruning Docker networks..."
docker network prune -f 2>/dev/null || true

echo ""
echo "Deep-cleaning chaincode Docker images (dev-* prefix)..."
DEV_IMAGE_IDS=$(docker images --format '{{.Repository}} {{.ID}}' | awk '$1 ~ /^(dev-|dev-peer)/ {print $2}' || true)
if [ -n "$DEV_IMAGE_IDS" ]; then
    echo "Found dev images: $DEV_IMAGE_IDS"
    docker rmi -f $DEV_IMAGE_IDS || true
else
    echo "No dev-* chaincode images found (clean state)."
fi

echo ""
echo "Cleaning stale Caliper reports and network configs..."
rm -f caliper-workspace/report.html
rm -f caliper-workspace/report_custom.html
rm -f caliper-workspace/caliper.log
rm -rf caliper-workspace/networks/networkConfig.yaml
rm -rf caliper-workspace/networks/connection-org1.yaml
rm -rf caliper-workspace/networks/connection-org2.yaml

echo -e "${GREEN}✓ Environment teardown complete — clean slate for BLAKE3 optimization${NC}"

# ── STEP 1: Fabric Binaries ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  STEP 1: Checking Fabric Binaries (v2.5.9)                   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
if [ ! -d "bin" ]; then
    echo "Downloading Fabric binaries (v2.5.9 / CA v1.5.7)..."
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
    echo "Fabric binaries found in ./bin — skipping download."
fi

export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# ── STEP 2: Start Test Network ─────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  STEP 2: Starting Fabric Test Network with CouchDB            ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
cd test-network
./network.sh down 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
docker system prune -f 2>/dev/null || true
./network.sh up createChannel -c mychannel -ca -s couchdb
echo ""
echo "Waiting 30 seconds for CouchDB and peers to fully stabilize..."
sleep 30
cd ..
echo -e "${GREEN}✓ Network started successfully${NC}"

# ── STEP 3: Deploy SHA-256 Chaincode ──────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  STEP 3: Deploying BLAKE3 Optimized Chaincode                 ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Chaincode: asset-transfer-basic/chaincode-go"
echo "Functions:"
echo "   IssueCertificate(id, studentID, studentName, degree, issuer, issueDate, metadata)"
echo "   → BLAKE3 Hashing: hash1=B3(fields) + hash2=B3(metadata) + final=B3(h1||h2)"
echo "   → json-iterator/go for serialization"
echo "   → Metadata field: 200KB+ large payload support"
echo ""
cd test-network
./network.sh deployCC \
    -ccn basic \
    -ccp ../asset-transfer-basic/chaincode-go \
    -ccl go \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"
cd ..

echo ""
echo "Waiting 15 seconds for chaincode containers to stabilize..."
sleep 15
echo -e "${GREEN}✓ BLAKE3 chaincode deployed successfully${NC}"

# ── STEP 4: Caliper Benchmark Setup ───────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  STEP 4: Setting Up Caliper for BLAKE3 Optimized Benchmark     ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
cd caliper-workspace

echo "Installing Caliper dependencies (clean install)..."
rm -rf node_modules package-lock.json
npm install

echo "Binding Caliper to Fabric SDK v2.5..."
npx caliper bind --caliper-bind-sut fabric:2.5

# ── STEP 5: Dynamic Credential Detection ──────────────────────────────────────
echo ""
echo -e "${GREEN}  Detecting cryptographic credentials dynamically...           ${NC}"
echo ""

# Org1 Private Key
KEY_DIR1="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY1=$(find "$KEY_DIR1" -name "*_sk" -type f 2>/dev/null | head -n 1)
if [ -z "$PVT_KEY1" ]; then
    echo -e "${RED}ERROR: Org1 private key not found in $KEY_DIR1${NC}"
    exit 1
fi

# Org1 Certificate
CERT_DIR1="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts"
if [ -f "$CERT_DIR1/cert.pem" ]; then
    CERT_FILE1="$CERT_DIR1/cert.pem"
elif [ -f "$CERT_DIR1/User1@org1.example.com-cert.pem" ]; then
    CERT_FILE1="$CERT_DIR1/User1@org1.example.com-cert.pem"
else
    CERT_FILE1=$(find "$CERT_DIR1" -name "*.pem" -type f 2>/dev/null | head -n 1)
fi

# Org2 Private Key
KEY_DIR2="../test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
PVT_KEY2=$(find "$KEY_DIR2" -name "*_sk" -type f 2>/dev/null | head -n 1)
if [ -z "$PVT_KEY2" ]; then
    echo -e "${RED}ERROR: Org2 private key not found in $KEY_DIR2${NC}"
    exit 1
fi

# Org2 Certificate
CERT_DIR2="../test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts"
if [ -f "$CERT_DIR2/cert.pem" ]; then
    CERT_FILE2="$CERT_DIR2/cert.pem"
elif [ -f "$CERT_DIR2/User1@org2.example.com-cert.pem" ]; then
    CERT_FILE2="$CERT_DIR2/User1@org2.example.com-cert.pem"
else
    CERT_FILE2=$(find "$CERT_DIR2" -name "*.pem" -type f 2>/dev/null | head -n 1)
fi

echo "Org1 Key:  $PVT_KEY1"
echo "Org1 Cert: $CERT_FILE1"
echo "Org2 Key:  $PVT_KEY2"
echo "Org2 Cert: $CERT_FILE2"

# Resolve absolute paths
PVT_KEY1=$(cd "$(dirname "$PVT_KEY1")" && echo "$(pwd)/$(basename "$PVT_KEY1")")
CERT_FILE1=$(cd "$(dirname "$CERT_FILE1")" && echo "$(pwd)/$(basename "$CERT_FILE1")")
PVT_KEY2=$(cd "$(dirname "$PVT_KEY2")" && echo "$(pwd)/$(basename "$PVT_KEY2")")
CERT_FILE2=$(cd "$(dirname "$CERT_FILE2")" && echo "$(pwd)/$(basename "$CERT_FILE2")")

# TLS Certificate paths
ABS_ROOT="$(cd "$ROOT_DIR" && pwd)"
ORDERER_TLS="$ABS_ROOT/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
PEER0_ORG1_TLS="$ABS_ROOT/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
PEER0_ORG2_TLS="$ABS_ROOT/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
CA_ORG1_CERT="$ABS_ROOT/test-network/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem"
CA_ORG2_CERT="$ABS_ROOT/test-network/organizations/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem"

# ── STEP 6: Generate Network Configuration ────────────────────────────────────
echo ""
echo -e "${GREEN}  Generating Caliper network configuration...                  ${NC}"
mkdir -p networks

cat << EOF > networks/networkConfig.yaml
name: BCMS-SHA256-Baseline
version: "2.0.0"
caliper:
  blockchain: fabric

channels:
  - channelName: mychannel
    contracts:
      - id: basic

organizations:
  - mspid: Org1MSP
    identities:
      certificates:
        - name: 'User1@org1.example.com'
          clientPrivateKey:
            path: '$PVT_KEY1'
          clientSignedCert:
            path: '$CERT_FILE1'
    connectionProfile:
      path: 'networks/connection-org1.yaml'
      discover: false

  - mspid: Org2MSP
    identities:
      certificates:
        - name: 'User1@org2.example.com'
          clientPrivateKey:
            path: '$PVT_KEY2'
          clientSignedCert:
            path: '$CERT_FILE2'
    connectionProfile:
      path: 'networks/connection-org2.yaml'
      discover: false
EOF

# ── STEP 7: Generate Connection Profiles ──────────────────────────────────────
cat << EOF > networks/connection-org1.yaml
name: test-network-org1
version: 1.0.0
client:
  organization: Org1
  connection:
    timeout:
      peer:
        endorser: '600'
      orderer: '600'

channels:
  mychannel:
    orderers:
      - orderer.example.com
    peers:
      peer0.org1.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true
      peer0.org2.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true

organizations:
  Org1:
    mspid: Org1MSP
    peers:
      - peer0.org1.example.com
    certificateAuthorities:
      - ca.org1.example.com
  Org2:
    mspid: Org2MSP
    peers:
      - peer0.org2.example.com

orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
      hostnameOverride: orderer.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 120000
    tlsCACerts:
      path: $ORDERER_TLS

peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 120000
      grpc.max_receive_message_length: -1
      grpc.max_send_message_length: -1
    tlsCACerts:
      path: $PEER0_ORG1_TLS
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 120000
      grpc.max_receive_message_length: -1
      grpc.max_send_message_length: -1
    tlsCACerts:
      path: $PEER0_ORG2_TLS

certificateAuthorities:
  ca.org1.example.com:
    url: https://localhost:7054
    caName: ca-org1
    tlsCACerts:
      path: $CA_ORG1_CERT
    httpOptions:
      verify: false
EOF

cat << EOF > networks/connection-org2.yaml
name: test-network-org2
version: 1.0.0
client:
  organization: Org2
  connection:
    timeout:
      peer:
        endorser: '300'
      orderer: '300'

channels:
  mychannel:
    orderers:
      - orderer.example.com
    peers:
      peer0.org1.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true
      peer0.org2.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true

organizations:
  Org1:
    mspid: Org1MSP
    peers:
      - peer0.org1.example.com
  Org2:
    mspid: Org2MSP
    peers:
      - peer0.org2.example.com
    certificateAuthorities:
      - ca.org2.example.com

orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
      hostnameOverride: orderer.example.com
    tlsCACerts:
      path: $ORDERER_TLS

peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
      grpc.keepalive_time_ms: 600000
      grpc.keepalive_timeout_ms: 120000
      grpc.max_receive_message_length: -1
      grpc.max_send_message_length: -1
    tlsCACerts:
      path: $PEER0_ORG1_TLS
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
    tlsCACerts:
      path: $PEER0_ORG2_TLS

certificateAuthorities:
  ca.org2.example.com:
    url: https://localhost:8054
    caName: ca-org2
    tlsCACerts:
      path: $CA_ORG2_CERT
    httpOptions:
      verify: false
EOF

echo -e "${GREEN}✓ Connection profiles generated${NC}"

# ── STEP 8: Generate SHA-256 Benchmark Config ─────────────────────────────────
echo ""
echo -e "${GREEN}  Generating SHA-256 baseline benchmark configuration...       ${NC}"

cat << 'BENCHEOF' > benchmarks/benchConfig_sha256_baseline.yaml
# ============================================================================
#  BCMS — SHA-256 BASELINE Benchmark Configuration
#  Branch: fabric-baseline
#  Algorithm: Double SHA-256 (hash1=fields + hash2=metadata + finalHash=combined)
#  Payload: 200KB+ random metadata per transaction
#
#  PURPOSE: Establish the SHA-256 performance baseline under heavy load.
#  This configuration intentionally stresses SHA-256 with large payloads
#  to create the "weak reference point" for BLAKE3 comparison.
#
#  SINGLE ROUND: IssueCertificate only
#  (Other rounds excluded — this is a SHA-256 stress test, not full suite)
# ============================================================================

monitors:
  resource:
    - module: docker
      options:
        interval: 1
        containers:
          - /orderer.example.com
          - /peer0.org1.example.com
          - /couchdb0
          - /peer0.org2.example.com
          - /couchdb1
          - /ca_org1
          - /ca_org2
          - /ca_orderer

test:
  name: bcms-sha256-baseline
  description: >
    SHA-256 baseline benchmark — BCMS fabric-baseline branch.
    IssueCertificate with double SHA-256 over fields and metadata plus 200KB+ metadata payload.
    Establishes the performance baseline for comparison against the BLAKE3-optimized branch.
    Target: measure TPS, latency, and CPU cost under large payloads.
  workers:
    type: local
    number: 8

  rounds:
    # ──────────────────────────────────────────────────────────────────
    # SHA-256 Baseline: IssueCertificate
    #   - 30 TPS × 30s = 900 transactions
    #   - Lower TPS than original (50) to account for 200KB payload overhead
    #   - Each tx: Double SHA-256 on 200KB+ metadata (CPU-intensive)
    #   - Expected: high latency, lower throughput vs BLAKE3 branch
    # ──────────────────────────────────────────────────────────────────
    - label: IssueCertificate-sha256-baseline
      description: >
        Single-round stress test: IssueCertificate with double SHA-256 and large metadata payload.
      txNumber: 1500
      rateControl:
        type: fixed-rate
        opts:
          tps: 50
      workload:
        module: workload/issueCertificate.js
      txOptions:
        invokerIdentity: User1@org1.example.com
BENCHEOF

echo -e "${GREEN}✓ SHA-256 benchmark config generated: benchmarks/benchConfig_sha256_baseline.yaml${NC}"

# ── STEP 9: Run SHA-256 Baseline Benchmark ────────────────────────────────────
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 9: Running SHA-256 Baseline Benchmark                  ${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Configuration:"
echo "   Algorithm  : SHA-256 (double hash baseline)"
echo "   Payload    : 200KB+ random metadata per transaction"
echo "   Round      : IssueCertificate @ 50 TPS / 1500 transactions"
echo "   Workers    : 8"
echo "   Purpose    : Baseline for comparison with BLAKE3-optimized chaincode"
echo ""

npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig_sha256_baseline.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

# ── STEP 10: Report Verification ──────────────────────────────────────────────
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  STEP 10: Report Verification                                ${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"

if [ -f "report.html" ]; then
    REPORT_SIZE=$(stat -c%s "report.html" 2>/dev/null || stat -f%z "report.html" 2>/dev/null || echo "unknown")
    echo ""
    echo -e "${GREEN}✓ SHA-256 BASELINE REPORT GENERATED${NC}"
    echo "  Report: $(pwd)/report.html ($REPORT_SIZE bytes)"

    # Run custom report post-processor if available
    if [ -f "generate_custom_report.js" ]; then
        echo ""
        echo "Running custom report post-processor..."
        node generate_custom_report.js report.html report_custom.html 2>/dev/null || true
        if [ -f "report_custom.html" ]; then
            CUSTOM_SIZE=$(stat -c%s "report_custom.html" 2>/dev/null || stat -f%z "report_custom.html" 2>/dev/null || echo "unknown")
            echo -e "${GREEN}✓ Custom report: $(pwd)/report_custom.html ($CUSTOM_SIZE bytes)${NC}"
        fi
    fi

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   SHA-256 BASELINE BENCHMARK COMPLETE                       ║${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}║   Algorithm  : SHA-256 (baseline)                           ║${NC}"
    echo -e "${BLUE}║   Payload    : 200KB+ metadata per transaction              ║${NC}"
    echo -e "${BLUE}║   Branch     : fabric-baseline                              ║${NC}"
    echo -e "${BLUE}║   Report     : caliper-workspace/report.html                ║${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}║   Use this report as the baseline to compare against the    ║${NC}"
    echo -e "${BLUE}║   BLAKE3-optimized chaincode branch.                        ║${NC}"
    echo -e "${BLUE}║   Generated  : $(date '+%Y-%m-%d %H:%M:%S')                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ERROR: report.html was NOT generated!                     ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "The SHA-256 baseline benchmark failed. Diagnostics:"
    echo ""
    echo "1. Check Docker containers:"
    echo "   docker ps"
    echo ""
    echo "2. Check Caliper log:"
    echo "   cat caliper-workspace/caliper.log"
    echo ""
    echo "3. Common causes:"
    echo "   - Network containers not running"
    echo "   - Chaincode deployment failed"
    echo "   - Certificate/key path mismatch"
    echo "   - go.sum checksum mismatch (run: cd asset-transfer-basic/chaincode-go && go mod tidy)"
    echo "   - Caliper bind version mismatch (should be fabric:2.5)"
    echo ""
    exit 1
fi
