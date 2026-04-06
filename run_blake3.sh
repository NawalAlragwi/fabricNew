#!/bin/bash
set -e

# ============================================================================
# BCMS — Blockchain Certificate Management System
# Master Automation Script: BLAKE3 ONLY Edition (Final Fixed)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${PROJECT_ROOT}/blake3_run_${TIMESTAMP}.log"

# ✅ الإصلاح الرئيسي: PATH يُعيَّن في أول السكريبت قبل أي أمر
# هذا يضمن أن كل subprocess يرث peer و configtxgen و discover
export PATH="${PROJECT_ROOT}/bin:$PATH"
export FABRIC_CFG_PATH="${PROJECT_ROOT}/config/"
export NODE_OPTIONS="--max-old-space-size=8192"

# ✅ تحقق فوري من وجود peer قبل البدء
if ! command -v peer &>/dev/null; then
    echo "ERROR: peer binary not found at ${PROJECT_ROOT}/bin/peer"
    echo "تأكدي من تحميل Fabric binaries أولاً"
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"; }
info()  { echo -e "${CYAN}[$(date '+%H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }

log "Starting BCMS BLAKE3 Benchmark — $(date)"
log "Project root: ${PROJECT_ROOT}"
log "peer binary: $(which peer)"
log "Log file: ${LOG_FILE}"

# ─── تنظيف التقارير القديمة ───────────────────────────────────────────────────
log "Cleaning old reports and logs..."
rm -f "${PROJECT_ROOT}/caliper-workspace/report.html" \
      "${PROJECT_ROOT}/caliper-workspace/report_custom.html" \
      "${PROJECT_ROOT}/caliper-workspace/caliper.log"

# ─── الخطوة 1: بناء الشبكة ────────────────────────────────────────────────────
log "Step 1: Rebuilding Fabric Network..."
cd "${PROJECT_ROOT}/test-network"
./network.sh down
docker volume prune -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true
./network.sh up createChannel -ca -s couchdb
sleep 20

# ─── الخطوة 2: نشر العقد الذكي (BLAKE3) ─────────────────────────────────────
log "Step 2: Deploying BLAKE3 Chaincode..."

log "Deploying chaincode on channel mychannel..."
./network.sh deployCC \
    -ccn basic \
    -ccp ../chaincode-bcms/blake3 \
    -ccl go \
    -ccv 1.0 \
    -ccs 1 \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

sleep 10
cd "${PROJECT_ROOT}"

# ─── الخطوة 3: تهيئة Caliper ─────────────────────────────────────────────────
log "Step 3: Preparing Caliper Workspace..."
cd "${PROJECT_ROOT}/caliper-workspace"

if [ ! -f "package.json" ]; then
    warn "package.json not found — creating it..."
    cat > package.json << 'PKGJSON'
{
  "name": "bcms-caliper-workspace",
  "version": "1.0.0",
  "description": "Caliper benchmark workspace for BCMS BLAKE3",
  "private": true,
  "engines": { "node": ">=18.0.0" },
  "dependencies": {
    "@hyperledger/caliper-cli": "0.6.0",
    "@hyperledger/caliper-fabric": "0.6.0"
  }
}
PKGJSON
    log "✓ package.json created"
fi

if [ -d "node_modules" ]; then
    log "Removing old node_modules..."
    rm -rf node_modules package-lock.json
fi

log "Installing Caliper dependencies..."
npm install --legacy-peer-deps 2>&1 | tee -a "$LOG_FILE"

log "Installing BLAKE3 native package..."
npm install blake3 --ignore-scripts --legacy-peer-deps 2>&1 | tee -a "$LOG_FILE" || \
    warn "blake3 native unavailable — workload will use SHA-256 fallback"

log "Binding Caliper to Fabric 2.5 SDK..."
npx caliper bind --caliper-bind-sut fabric:2.5 --legacy-peer-deps 2>&1 | tee -a "$LOG_FILE"

# ─── الخطوة 4: اكتشاف المفاتيح وتوليد الإعدادات ─────────────────────────────
log "Step 4: Detecting Keys and Generating Network Config..."
echo -e "${BOLD_BLUE}══════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"

ABS_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"

KEY_DIR1="${ABS_ROOT}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
CERT_DIR1="${ABS_ROOT}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts"
PVT_KEY1=$(find "${KEY_DIR1}" -name "*_sk" -type f 2>/dev/null | head -n 1)
CERT_FILE1="${CERT_DIR1}/cert.pem"

log "Detecting Org1 keys..."
if [ -z "$PVT_KEY1" ]; then
    error "Org1 private key not found — is the network running?"
    exit 1
fi

KEY_DIR2="${ABS_ROOT}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
CERT_DIR2="${ABS_ROOT}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts"
PVT_KEY2=$(find "${KEY_DIR2}" -name "*_sk" -type f 2>/dev/null | head -n 1)
CERT_FILE2="${CERT_DIR2}/cert.pem"

log "Detecting Org2 keys..."
if [ -z "$PVT_KEY2" ]; then
    error "Org2 private key not found — is the network running?"
    exit 1
fi

info "Org1 Key:  ${PVT_KEY1}"
info "Org1 Cert: ${CERT_FILE1}"
info "Org2 Key:  ${PVT_KEY2}"
info "Org2 Cert: ${CERT_FILE2}"

mkdir -p networks

cat > networks/connection-org1.yaml << 'CONNEOF'
name: connection-org1
version: "1.0.0"
client:
  organization: Org1MSP
  connection:
    timeout:
      peer:
        endorser: "300"
organizations:
  Org1MSP:
    mspid: Org1MSP
    peers:
      - peer0.org1.example.com
peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    tlsCACerts:
      path: /workspaces/fabricNew/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
CONNEOF

cat > networks/connection-org2.yaml << 'CONNEOF'
name: connection-org2
version: "1.0.0"
client:
  organization: Org2MSP
  connection:
    timeout:
      peer:
        endorser: "300"
organizations:
  Org2MSP:
    mspid: Org2MSP
    peers:
      - peer0.org2.example.com
peers:
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    tlsCACerts:
      path: /workspaces/fabricNew/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
CONNEOF

log "✓ connection-org1.yaml generated"
log "✓ connection-org2.yaml generated"

cat > networks/networkConfig.yaml << EOF
name: Caliper-BLAKE3
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
EOF

log "✓ networkConfig.yaml generated"

# ─── الخطوة 5: تشغيل Benchmark ───────────────────────────────────────────────
log "Step 5: Launching Caliper Benchmark (6 Rounds)..."

if [ -d "node_modules/fabric-network" ]; then
    log "Removing conflicting fabric-network binding..."
    rm -rf node_modules/fabric-network node_modules/fabric-common node_modules/fabric-ca-client
fi

npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-fabric-gateway-enabled \
    --caliper-report-path report.html \
    2>&1 | tee -a "$LOG_FILE"

# ─── الخطوة 6: التحقق من التقارير ────────────────────────────────────────────
if [ -f "report.html" ]; then
    log "SUCCESS: report.html generated."
    cp report.html "${PROJECT_ROOT}/report.html"

    if [ -f "generate_custom_report.js" ]; then
        log "Generating Custom PhD Report..."
        node generate_custom_report.js report.html report_custom.html
        cp report_custom.html "${PROJECT_ROOT}/report_custom.html"
    fi
    log "Final reports are available in the project root."
else
    error "Benchmark failed to generate report.html. Check caliper.log"
    exit 1
fi

cd "${PROJECT_ROOT}"
echo -e "${BOLD_BLUE}══════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
log "   BLAKE3 BENCHMARK COMPLETE"
echo -e "${BOLD_BLUE}══════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"