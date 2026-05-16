#!/bin/bash
# ============================================================================
# تشغيل Caliper فقط (الشبكة والـchaincode جاهزان)
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ABS_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${PROJECT_ROOT}/caliper_only_${TIMESTAMP}.log"

export PATH="${PROJECT_ROOT}/bin:$PATH"
export FABRIC_CFG_PATH="${PROJECT_ROOT}/config/"
export NODE_OPTIONS="--max-old-space-size=8192"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"; }
info()  { echo -e "${CYAN}[$(date '+%H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }

log "=== Caliper Only Run — $(date) ==="
log "Project root: ${ABS_ROOT}"
# تصحيح مسار getcwd() إذا كان المجلد قد تغير
cd "${ABS_ROOT}"

# ─── الخطوة 0: مزامنة ساعة WSL لمنع Clock Drift (قيم سالبة) ─────────────────
log "Step 0: Checking and syncing WSL2 clock..."
if grep -qi microsoft /proc/version 2>/dev/null; then
    info "Syncing time with pool.ntp.org..."
    if ! sudo -n true 2>/dev/null; then
        warn "Please enter your sudo password to sync system clock:"
    fi
    if sudo ntpdate -u pool.ntp.org; then
        log "✅ WSL2 clock successfully synced."
    else
        warn "Clock sync failed. If you see negative latency, run 'sudo ntpdate -u pool.ntp.org' manually."
    fi
else
    log "Not running in WSL2 — skipping clock sync"
fi

# ─── اكتشاف المفاتيح ────────────────────────────────────────────────────────
log "Detecting keys..."

KEY_DIR1="${ABS_ROOT}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
CERT_DIR1="${ABS_ROOT}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts"
PVT_KEY1=$(find "${KEY_DIR1}" -name "*_sk" -type f 2>/dev/null | head -n 1)
CERT_FILE1="${CERT_DIR1}/cert.pem"

KEY_DIR2="${ABS_ROOT}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
CERT_DIR2="${ABS_ROOT}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts"
PVT_KEY2=$(find "${KEY_DIR2}" -name "*_sk" -type f 2>/dev/null | head -n 1)
CERT_FILE2="${CERT_DIR2}/cert.pem"

if [ -z "$PVT_KEY1" ] || [ -z "$PVT_KEY2" ]; then
    error "Keys not found — is the network running?"
    exit 1
fi

info "Org1 Key:  ${PVT_KEY1}"
info "Org1 Cert: ${CERT_FILE1}"
info "Org2 Key:  ${PVT_KEY2}"
info "Org2 Cert: ${CERT_FILE2}"

# ─── توليد ملفات الاتصال ────────────────────────────────────────────────────
log "Generating network config files..."
cd "${PROJECT_ROOT}/caliper-workspace"
mkdir -p networks

TLS_CRT1="${ABS_ROOT}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
TLS_CRT2="${ABS_ROOT}/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

# التحقق من وجود ملفات TLS
if [ ! -f "$TLS_CRT1" ]; then
    error "TLS cert not found: $TLS_CRT1"
    exit 1
fi
log "✓ TLS certs verified"

cat > networks/connection-org1.yaml <<YAML
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
      path: ${TLS_CRT1}
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
YAML

cat > networks/connection-org2.yaml <<YAML
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
      path: ${TLS_CRT2}
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
YAML

cat > networks/networkConfig.yaml <<YAML
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
YAML

log "✓ All config files generated"

# التحقق من المسارات داخل الملف
log "Verifying TLS path in connection-org1.yaml:"
grep "path:" networks/connection-org1.yaml | tee -a "$LOG_FILE"

# ─── حذف fabric-network المتعارض ─────────────────────────────────────────────
if [ -d "node_modules/fabric-network" ]; then
    log "Removing conflicting fabric-network..."
    rm -rf node_modules/fabric-network node_modules/fabric-common node_modules/fabric-ca-client
fi

# ─── تشغيل Caliper ──────────────────────────────────────────────────────────
log "=== Launching Caliper Benchmark (6 Rounds) ==="
rm -f report.html

npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-fabric-gateway-enabled \
    --caliper-report-path report.html \
    2>&1 | tee -a "$LOG_FILE"

# ─── نتائج ──────────────────────────────────────────────────────────────────
if [ -f "report.html" ]; then
    log "✅ SUCCESS: report.html generated!"
    cp report.html "${PROJECT_ROOT}/report.html"
    log "Report copied to: ${PROJECT_ROOT}/report.html"
else
    error "❌ report.html not found — check log: $LOG_FILE"
    exit 1
fi

log "=== DONE ==="
