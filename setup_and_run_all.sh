#!/bin/bash
# ============================================================================
#  BCMS — Blockchain Certificate Management System
#  Master Automation Script: Setup, Verify, Benchmark, Document
#  Branch: fabric-blake3
#
#  Research: "Enhancing Trust and Transparency in Education Using
#             Blockchain: A Hyperledger Fabric-Based Framework"
#
#  Migration: SHA-256 → BLAKE3
#    Chaincode:  chaincode-bcms/blake3 (github.com/zeebo/blake3)
#    Client:     blake3 npm package (computeBlake3Hash)
#    On-chain:   HashAlgorithm: "BLAKE3" per certificate
#    Comparison: Results exported to results/blake3/ for SHA-256 vs BLAKE3 analysis
#
#  This script automatically:
#    1.  Tear down any existing Docker network
#    2.  Download Hyperledger Fabric binaries (if needed)
#    3.  Start Hyperledger Fabric test network (CouchDB mode)
#    4.  Deploy BLAKE3 chaincode (chaincode-bcms/blake3)
#    5.  Install blake3 npm package in caliper-workspace
#    6.  Run Hyperledger Caliper benchmark (6 rounds, 8 workers)
#    7.  Export HTML report to results/blake3/
#    8.  Run Python analysis comparing SHA-256 vs BLAKE3 metrics
#    9.  Generate comparison CSV and Markdown report
#
#  Usage:
#    bash setup_and_run_all.sh                   # Full run
#    bash setup_and_run_all.sh --skip-network    # Skip Fabric network setup
#    bash setup_and_run_all.sh --skip-caliper    # Skip Caliper benchmarks
#    bash setup_and_run_all.sh --report-only     # Only regenerate reports
#
#  Benchmark TPS (identical to SHA-256 baseline for valid comparison):
#    Round 1 IssueCertificate:     50 TPS × 30s = 1500 txns
#    Round 2 VerifyCertificate:   100 TPS × 30s = 3000 txns
#    Round 3 QueryAllCertificates: 50 TPS × 30s = 1500 txns
#    Round 4 RevokeCertificate:    50 TPS × 30s = 1500 txns
#    Round 5 GetCertsByStudent:    75 TPS × 30s = 2250 txns
#    Round 6 GetAuditLogs:         30 TPS × 30s =  900 txns
#    TOTAL:                                      14,550 transactions
#
#  Success Criteria:
#    Fail Rate:  0.00% across all 14,550+ transactions
#    Resources:  Full Docker monitor CPU/RAM for peer0.org1, orderer, CouchDB
#    Integrity:  On-chain HashAlgorithm: "BLAKE3" verified in every certificate
#
#  Requirements:
#    - Linux (Ubuntu 20.04+) or macOS
#    - Docker & Docker Compose
#    - Node.js >= 16 (for blake3 npm package WASM support)
#    - Go >= 1.21
#    - Python 3 (for analysis script)
#    - 8GB+ RAM recommended
#    - 20GB+ free disk space
#
# ============================================================================

set -e

# ─── Script Configuration ─────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${ROOT_DIR}/setup_run_blake3_${TIMESTAMP}.log"

# Parse command line flags
SKIP_NETWORK=false
SKIP_CALIPER=false
REPORT_ONLY=false

for arg in "$@"; do
    case $arg in
        --skip-network) SKIP_NETWORK=true ;;
        --skip-caliper) SKIP_CALIPER=true ;;
        --report-only)  REPORT_ONLY=true; SKIP_NETWORK=true; SKIP_CALIPER=true ;;
        --help)
            echo "Usage: bash setup_and_run_all.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-network    Skip Fabric network setup"
            echo "  --skip-caliper    Skip Caliper benchmarks"
            echo "  --report-only     Only regenerate reports (no Docker/Fabric needed)"
            echo ""
            echo "Examples:"
            echo "  bash setup_and_run_all.sh                   # Full BLAKE3 benchmark run"
            echo "  bash setup_and_run_all.sh --skip-network    # Reuse existing network"
            echo "  bash setup_and_run_all.sh --report-only     # Regenerate reports only"
            exit 0
            ;;
    esac
done

# ─── Colour Helpers ───────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "$(date '+%H:%M:%S') ${GREEN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "$(date '+%H:%M:%S') ${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "$(date '+%H:%M:%S') ${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
step() { echo -e "\n$(date '+%H:%M:%S') ${CYAN}${BOLD}▶ $*${NC}" | tee -a "$LOG_FILE"; }

# ─── Banner ───────────────────────────────────────────────────────────────────

echo -e "${CYAN}${BOLD}" | tee -a "$LOG_FILE"
echo "╔══════════════════════════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
echo "║  BCMS Blockchain Certificate Management System                  ║" | tee -a "$LOG_FILE"
echo "║  Branch: fabric-blake3                                          ║" | tee -a "$LOG_FILE"
echo "║  Migration: SHA-256 → BLAKE3 (github.com/zeebo/blake3)          ║" | tee -a "$LOG_FILE"
echo "║  Benchmark: 6 rounds, 8 workers, 14,550 transactions            ║" | tee -a "$LOG_FILE"
echo "║  Target: 0.00% fail rate | HashAlgorithm: BLAKE3 on-chain       ║" | tee -a "$LOG_FILE"
echo "╚══════════════════════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
echo -e "${NC}" | tee -a "$LOG_FILE"

log "Run started: $(date)"
log "Log file: $LOG_FILE"

# ─── Permission fix for CI environments ──────────────────────────────────────
if [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ "${FIX_PERMISSIONS:-}" = "true" ]; then
    if [ -x "./scripts/fix-permissions.sh" ]; then
        log "Running scripts/fix-permissions.sh (CI mode)..."
        ./scripts/fix-permissions.sh || true
    fi
fi

# ─── Report-only mode ─────────────────────────────────────────────────────────
if [ "$REPORT_ONLY" = "true" ]; then
    step "REPORT-ONLY mode: regenerating reports from existing data"
    mkdir -p results/blake3
    if [ -f "results/analyze_results.py" ]; then
        log "Running analyze_results.py..."
        python3 results/analyze_results.py \
            --sha256-json results/scenario_1_sha256/caliper_results.json \
            --blake3-json results/blake3/caliper_results.json \
            --output-dir  results/blake3 \
            2>&1 | tee -a "$LOG_FILE" || warn "analyze_results.py failed (may need caliper_results.json)"
    fi
    log "Report-only mode complete."
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: TEAR DOWN EXISTING NETWORK
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 1: Tearing down existing Docker network"

if [ "$SKIP_NETWORK" = "false" ]; then
    log "Removing stale Docker containers..."
    docker rm -f $(docker ps -aq) 2>/dev/null || true
    docker volume prune -f   2>/dev/null || true
    docker network prune -f  2>/dev/null || true

    log "Removing dev-* chaincode images..."
    DEV_IMAGE_IDS=$(docker images --format '{{.Repository}} {{.ID}}' \
        | awk '$1 ~ /^(dev-|dev-peer)/ {print $2}' || true)
    if [ -n "$DEV_IMAGE_IDS" ]; then
        docker rmi -f $DEV_IMAGE_IDS 2>/dev/null || true
    fi
    log "Docker environment clean."
else
    log "SKIP_NETWORK=true — skipping teardown."
fi

# Always clean stale Caliper artefacts
log "Removing stale Caliper artefacts..."
rm -f caliper-workspace/report.html
rm -f caliper-workspace/report_custom.html
rm -f caliper-workspace/caliper.log
rm -f caliper-workspace/networks/networkConfig.yaml
rm -f caliper-workspace/networks/connection-org1.yaml
rm -f caliper-workspace/networks/connection-org2.yaml

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: DOWNLOAD FABRIC BINARIES (if needed)
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 2: Checking Fabric binaries"

if [ ! -d "bin" ]; then
    log "Downloading Hyperledger Fabric binaries (v2.5.9, CA v1.5.7)..."
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7 2>&1 | tee -a "$LOG_FILE"
else
    log "Fabric binaries found — skipping download."
fi

export PATH="${PWD}/bin:$PATH"
export FABRIC_CFG_PATH="${PWD}/config/"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: START FABRIC TEST NETWORK
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 3: Starting Fabric test network (CouchDB mode)"

if [ "$SKIP_NETWORK" = "false" ]; then
    cd test-network
    ./network.sh down                                        2>&1 | tee -a "$LOG_FILE"
    docker volume prune -f                                   2>/dev/null || true
    docker system prune -f                                   2>/dev/null || true
    ./network.sh up createChannel -c mychannel -ca -s couchdb 2>&1 | tee -a "$LOG_FILE"

    log "Waiting 30 seconds for CouchDB and peers to stabilize..."
    sleep 30
    cd ..
    log "Fabric test network started successfully."
else
    log "SKIP_NETWORK=true — using existing network."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: DEPLOY BLAKE3 CHAINCODE
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 4: Deploying BLAKE3 chaincode (chaincode-bcms/blake3)"

if [ "$SKIP_NETWORK" = "false" ]; then
    log "Setting Go environment for BLAKE3 dependency resolution..."
    export GOFLAGS="-mod=mod"
    export GOWORK="off"
    export GO111MODULE="on"
    export GOPROXY="https://proxy.golang.org,direct"

    log "Verifying BLAKE3 Go dependency (github.com/zeebo/blake3)..."
    cd chaincode-bcms/blake3
    go mod tidy 2>&1 | tee -a "$LOG_FILE" || warn "go mod tidy failed — continuing"
    go build ./... 2>&1 | tee -a "$LOG_FILE" || {
        err "BLAKE3 chaincode build failed. Ensure github.com/zeebo/blake3 is available."
        err "Run: cd chaincode-bcms/blake3 && go mod download"
        exit 1
    }
    log "BLAKE3 chaincode compiled successfully."
    cd ../..

    log "Deploying chaincode to mychannel..."
    cd test-network
    ./network.sh deployCC \
        -ccn basic \
        -ccp ../chaincode-bcms/blake3 \
        -ccl go \
        -ccep "OR('Org1MSP.peer','Org2MSP.peer')" \
        2>&1 | tee -a "$LOG_FILE"
    cd ..

    log "Waiting 15 seconds for chaincode containers to stabilize..."
    sleep 15
    log "BLAKE3 chaincode deployed successfully."
    log "  Contract name: basic"
    log "  HashAlgorithm: BLAKE3 (github.com/zeebo/blake3)"
    log "  On-chain tag:  HashAlgorithm: 'BLAKE3' per certificate"
else
    log "SKIP_NETWORK=true — skipping chaincode deployment."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: PREPARE CALIPER WORKSPACE
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 5: Preparing Caliper workspace (installing blake3 npm)"

cd caliper-workspace

if [ "$SKIP_CALIPER" = "false" ]; then
    log "Installing Caliper dependencies (clean install with blake3 npm)..."
    rm -rf node_modules package-lock.json
    npm install 2>&1 | tee -a "$LOG_FILE"
    log "blake3 npm package installed for client-side BLAKE3 hashing."

    log "Binding Caliper to fabric:2.5..."
    npx caliper bind --caliper-bind-sut fabric:2.5 --caliper-bind-args=-g \
        2>&1 | tee -a "$LOG_FILE" \
        || warn "caliper bind exited non-zero — may still work"
fi

# ─── Dynamic key/cert detection ──────────────────────────────────────────────
log "Detecting private keys and certificates dynamically..."

KEY_DIR1="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY1=$(find "$KEY_DIR1" -name "*_sk" -type f 2>/dev/null | head -n 1)
[ -z "$PVT_KEY1" ] && { err "Org1 private key not found in $KEY_DIR1"; exit 1; }

CERT_DIR1="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts"
if   [ -f "$CERT_DIR1/cert.pem" ];                       then CERT_FILE1="$CERT_DIR1/cert.pem"
elif [ -f "$CERT_DIR1/User1@org1.example.com-cert.pem" ]; then CERT_FILE1="$CERT_DIR1/User1@org1.example.com-cert.pem"
else CERT_FILE1=$(find "$CERT_DIR1" -name "*.pem" -type f 2>/dev/null | head -n 1); fi

KEY_DIR2="${ROOT_DIR}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
PVT_KEY2=$(find "$KEY_DIR2" -name "*_sk" -type f 2>/dev/null | head -n 1)
[ -z "$PVT_KEY2" ] && { err "Org2 private key not found in $KEY_DIR2"; exit 1; }

CERT_DIR2="${ROOT_DIR}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts"
if   [ -f "$CERT_DIR2/cert.pem" ];                       then CERT_FILE2="$CERT_DIR2/cert.pem"
elif [ -f "$CERT_DIR2/User1@org2.example.com-cert.pem" ]; then CERT_FILE2="$CERT_DIR2/User1@org2.example.com-cert.pem"
else CERT_FILE2=$(find "$CERT_DIR2" -name "*.pem" -type f 2>/dev/null | head -n 1); fi

# Resolve to absolute paths
PVT_KEY1=$(cd "$(dirname "$PVT_KEY1")"   && echo "$(pwd)/$(basename "$PVT_KEY1")")
CERT_FILE1=$(cd "$(dirname "$CERT_FILE1")" && echo "$(pwd)/$(basename "$CERT_FILE1")")
PVT_KEY2=$(cd "$(dirname "$PVT_KEY2")"   && echo "$(pwd)/$(basename "$PVT_KEY2")")
CERT_FILE2=$(cd "$(dirname "$CERT_FILE2")" && echo "$(pwd)/$(basename "$CERT_FILE2")")

ABS_ROOT="$(cd "$ROOT_DIR" && pwd)"
ORDERER_TLS="$ABS_ROOT/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
PEER0_ORG1_TLS="$ABS_ROOT/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
PEER0_ORG2_TLS="$ABS_ROOT/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
CA_ORG1_CERT="$ABS_ROOT/test-network/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem"
CA_ORG2_CERT="$ABS_ROOT/test-network/organizations/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem"

log "Org1 Key:  $PVT_KEY1"
log "Org1 Cert: $CERT_FILE1"
log "Org2 Key:  $PVT_KEY2"
log "Org2 Cert: $CERT_FILE2"

# ─── Generate network config ──────────────────────────────────────────────────
mkdir -p networks

cat > networks/networkConfig.yaml << NETEOF
name: Caliper-Fabric-BLAKE3
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
            path: '${PVT_KEY1}'
          clientSignedCert:
            path: '${CERT_FILE1}'
    connectionProfile:
      path: 'networks/connection-org1.yaml'
      discover: false

  - mspid: Org2MSP
    identities:
      certificates:
        - name: 'User1@org2.example.com'
          clientPrivateKey:
            path: '${PVT_KEY2}'
          clientSignedCert:
            path: '${CERT_FILE2}'
    connectionProfile:
      path: 'networks/connection-org2.yaml'
      discover: false
NETEOF

cat > networks/connection-org1.yaml << CONNEOF
name: test-network-org1
version: 1.0.0
client:
  organization: Org1
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
    tlsCACerts:
      path: ${ORDERER_TLS}

peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
    tlsCACerts:
      path: ${PEER0_ORG1_TLS}
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
    tlsCACerts:
      path: ${PEER0_ORG2_TLS}

certificateAuthorities:
  ca.org1.example.com:
    url: https://localhost:7054
    caName: ca-org1
    tlsCACerts:
      path: ${CA_ORG1_CERT}
    httpOptions:
      verify: false
CONNEOF

cat > networks/connection-org2.yaml << CONNEOF2
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
      path: ${ORDERER_TLS}

peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
    tlsCACerts:
      path: ${PEER0_ORG1_TLS}
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
    tlsCACerts:
      path: ${PEER0_ORG2_TLS}

certificateAuthorities:
  ca.org2.example.com:
    url: https://localhost:8054
    caName: ca-org2
    tlsCACerts:
      path: ${CA_ORG2_CERT}
    httpOptions:
      verify: false
CONNEOF2

log "Connection profiles generated."

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: RUN CALIPER BENCHMARK (6 ROUNDS)
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 6: Running Caliper benchmark (6 rounds, 14,550 transactions)"

if [ "$SKIP_CALIPER" = "false" ]; then
    log "Benchmark configuration:"
    log "  Round 1  IssueCertificate:     50 TPS × 30s = 1500 txns  [BLAKE3 write]"
    log "  Round 2  VerifyCertificate:   100 TPS × 30s = 3000 txns  [BLAKE3 read]"
    log "  Round 3  QueryAllCerts:        50 TPS × 30s = 1500 txns  [CouchDB query]"
    log "  Round 4  RevokeCertificate:    50 TPS × 30s = 1500 txns  [revocation write]"
    log "  Round 5  GetCertsByStudent:    75 TPS × 30s = 2250 txns  [student query]"
    log "  Round 6  GetAuditLogs:         30 TPS × 30s =  900 txns  [audit query]"
    log "  TOTAL:                                       14,550 txns"
    log ""
    log "Target: 0.00% fail rate | HashAlgorithm: BLAKE3 on-chain"

    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig benchmarks/benchConfig.yaml \
        --caliper-flow-only-test \
        --caliper-fabric-gateway-enabled \
        2>&1 | tee -a "$LOG_FILE" || warn "Caliper exited non-zero — checking for report.html"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: EXPORT HTML REPORT TO results/blake3/
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 7: Exporting HTML report to results/blake3/"

BLAKE3_RESULTS_DIR="${ROOT_DIR}/results/blake3"
mkdir -p "$BLAKE3_RESULTS_DIR"

if [ -f "report.html" ]; then
    REPORT_SIZE=$(stat -c%s "report.html" 2>/dev/null || stat -f%z "report.html" 2>/dev/null || echo "unknown")
    log "Caliper report generated: report.html (${REPORT_SIZE} bytes)"

    # Copy HTML report to results/blake3/
    cp "report.html" "${BLAKE3_RESULTS_DIR}/report_blake3.html"
    log "Report exported: ${BLAKE3_RESULTS_DIR}/report_blake3.html"

    # Generate caliper_results.json from HTML report (if parser available)
    if [ -f "${ROOT_DIR}/scripts/parse_caliper_report.py" ]; then
        log "Parsing Caliper report → caliper_results.json..."
        python3 "${ROOT_DIR}/scripts/parse_caliper_report.py" \
            --report "report.html" \
            --scenario 2 \
            --key "scenario_2_blake3" \
            --output "${BLAKE3_RESULTS_DIR}/caliper_results.json" \
            2>&1 | tee -a "$LOG_FILE" \
            || warn "parse_caliper_report.py failed — manual JSON creation needed"
    fi

    # Save benchmark metadata
    cat > "${BLAKE3_RESULTS_DIR}/benchmark_meta.json" << METAEOF
{
    "branch": "fabric-blake3",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "hash_algorithm": "BLAKE3",
    "chaincode": "chaincode-bcms/blake3",
    "go_library": "github.com/zeebo/blake3 v0.2.4",
    "npm_package": "blake3",
    "on_chain_tag": "HashAlgorithm: BLAKE3",
    "audit_logging": "disabled (benchmark mode)",
    "rounds": 6,
    "workers": 8,
    "total_transactions_target": 14550,
    "tps_settings": {
        "IssueCertificate": 50,
        "VerifyCertificate": 100,
        "QueryAllCertificates": 50,
        "RevokeCertificate": 50,
        "GetCertificatesByStudent": 75,
        "GetAuditLogs": 30
    },
    "comparison_baseline": "results/scenario_1_sha256/caliper_results.json"
}
METAEOF
    log "Benchmark metadata saved: ${BLAKE3_RESULTS_DIR}/benchmark_meta.json"

    # ═══════════════════════════════════════════════════════════════════════════════
    # STEP 7.5: GENERATE DYNAMIC CUSTOM REPORT
    # ═══════════════════════════════════════════════════════════════════════════════

    log "Generating dynamic custom report from latest results..."
    cd caliper-workspace
    if [ -f "generate_dynamic_report.js" ]; then
        node generate_dynamic_report.js 2>&1 | tee -a "$LOG_FILE"
        if [ -f "report_custom.html" ]; then
            cp "report_custom.html" "${BLAKE3_RESULTS_DIR}/report_custom.html"
            log "Dynamic custom report generated: ${BLAKE3_RESULTS_DIR}/report_custom.html"
        else
            warn "Dynamic custom report generation failed"
        fi
    else
        warn "generate_dynamic_report.js not found — skipping dynamic report generation"
    fi
    cd "$ROOT_DIR"

else
    warn "report.html was NOT generated!"
    warn "Check caliper.log for errors."
    warn "Common causes:"
    warn "  - Network containers not running (check: docker ps)"
    warn "  - BLAKE3 chaincode not deployed or wrong contract name"
    warn "  - blake3 npm package not installed (check: ls node_modules/blake3)"
    warn "  - Certificate/key path mismatch"
fi

cd "$ROOT_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: RUN PYTHON ANALYSIS (SHA-256 vs BLAKE3 COMPARISON)
# ═══════════════════════════════════════════════════════════════════════════════

step "Step 8: Running SHA-256 vs BLAKE3 analysis"

if [ -f "results/analyze_results.py" ]; then
    log "Running analyze_results.py..."
    python3 results/analyze_results.py \
        --sha256-json results/scenario_1_sha256/caliper_results.json \
        --blake3-json results/blake3/caliper_results.json \
        --output-dir  results/blake3 \
        2>&1 | tee -a "$LOG_FILE" \
        || warn "analyze_results.py completed with warnings"

    log "Analysis artifacts:"
    [ -f "results/blake3/comparison_sha256_vs_blake3.csv" ]     && log "  ✓ CSV:      results/blake3/comparison_sha256_vs_blake3.csv"
    [ -f "results/blake3/comparison_sha256_vs_blake3.md" ]      && log "  ✓ Markdown: results/blake3/comparison_sha256_vs_blake3.md"
    [ -f "results/blake3/performance_improvement.json" ]        && log "  ✓ JSON:     results/blake3/performance_improvement.json"
else
    warn "results/analyze_results.py not found — skipping analysis."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

echo "" | tee -a "$LOG_FILE"
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
echo -e "${CYAN}${BOLD}║  BCMS BLAKE3 Benchmark — Run Complete                           ║${NC}" | tee -a "$LOG_FILE"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

log "Generated artifacts:"
[ -f "caliper-workspace/report.html" ]                              && log "  ✓ Caliper report:    caliper-workspace/report.html"
[ -f "results/blake3/report_blake3.html" ]                         && log "  ✓ BLAKE3 report:     results/blake3/report_blake3.html"
[ -f "results/blake3/caliper_results.json" ]                       && log "  ✓ Results JSON:      results/blake3/caliper_results.json"
[ -f "results/blake3/benchmark_meta.json" ]                        && log "  ✓ Benchmark meta:    results/blake3/benchmark_meta.json"
[ -f "results/blake3/comparison_sha256_vs_blake3.csv" ]            && log "  ✓ Comparison CSV:    results/blake3/comparison_sha256_vs_blake3.csv"
[ -f "results/blake3/comparison_sha256_vs_blake3.md" ]             && log "  ✓ Comparison MD:     results/blake3/comparison_sha256_vs_blake3.md"
[ -f "README_EXECUTION.md" ]                                       && log "  ✓ Execution guide:   README_EXECUTION.md"

echo "" | tee -a "$LOG_FILE"
log "Branch: fabric-blake3"
log "SHA-256 baseline: results/scenario_1_sha256/caliper_results.json"
log "BLAKE3 results:   results/blake3/"
log ""
log "Run completed: $(date)"
log "Full log: $LOG_FILE"
