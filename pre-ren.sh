#!/bin/bash
# ============================================================================
#  BCMS — Pre-Deployment Setup Script
#  يُنفَّذ مرة واحدة قبل أي عملية نشر
#  يحل كل المشاكل التي تم رصدها خلال التطوير
# ============================================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${PROJECT_ROOT}/setup_$(date '+%Y%m%d_%H%M%S').log"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓] $*${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[✗] $*${NC}" | tee -a "$LOG_FILE"; exit 1; }
warn()  { echo -e "${YELLOW}[!] $*${NC}" | tee -a "$LOG_FILE"; }
info()  { echo -e "${CYAN}[→] $*${NC}" | tee -a "$LOG_FILE"; }

echo "============================================" | tee -a "$LOG_FILE"
echo " BCMS Pre-Deployment Setup" | tee -a "$LOG_FILE"
echo " $(date)" | tee -a "$LOG_FILE"
echo "============================================" | tee -a "$LOG_FILE"

# ─── الإصلاح 1: CRLF → LF (المشاكل 4 و 5) ───────────────────────────────────
info "Fix 1: Converting CRLF to LF on all script files..."

if ! command -v dos2unix &>/dev/null; then
    warn "dos2unix not found — installing..."
    sudo apt-get update -qq && sudo apt-get install -y -qq dos2unix
fi

find "${PROJECT_ROOT}" -type f \
    \( -name "*.sh" -o -name "*.config" -o -name "*.env" \
    -o -name "*.yaml" -o -name "*.json" -o -name "*.go" \) \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/vendor/*" \
    | xargs dos2unix 2>/dev/null

log "CRLF → LF conversion complete"

# ─── الإصلاح 2: Git line ending config (منع تكرار المشكلة) ──────────────────
info "Fix 2: Configuring git line endings..."

git -C "${PROJECT_ROOT}" config core.autocrlf false
git -C "${PROJECT_ROOT}" config core.eol lf

cat > "${PROJECT_ROOT}/.gitattributes" << 'EOF'
* text=auto
*.sh text eol=lf
*.go text eol=lf
*.yaml text eol=lf
*.json text eol=lf
*.env text eol=lf
*.config text eol=lf
*.md text eol=lf
EOF

log "Git line endings configured"

# ─── الإصلاح 3: Fabric binaries (المشكلة 3 و 12) ────────────────────────────
info "Fix 3: Checking Fabric binaries..."

if [ ! -f "${PROJECT_ROOT}/bin/peer" ]; then
    warn "peer binary not found — downloading Fabric binaries..."

    cd "${PROJECT_ROOT}"
    curl -L --retry 3 \
        "https://github.com/hyperledger/fabric/releases/download/v2.5.9/hyperledger-fabric-linux-amd64-2.5.9.tar.gz" \
        -o fabric-binaries.tar.gz 2>&1 | tee -a "$LOG_FILE"

    if [ ! -f "fabric-binaries.tar.gz" ]; then
        error "Failed to download Fabric binaries. Check internet connection."
    fi

    tar -xzf fabric-binaries.tar.gz
    rm -f fabric-binaries.tar.gz
    log "Fabric binaries downloaded and extracted"
else
    log "Fabric binaries already present: $(${PROJECT_ROOT}/bin/peer version 2>/dev/null | head -2)"
fi

# تصدير PATH في ~/.bashrc لضمان الإرث
if ! grep -q "fabricNew/bin" ~/.bashrc 2>/dev/null; then
    echo "export PATH=${PROJECT_ROOT}/bin:\$PATH" >> ~/.bashrc
    echo "export FABRIC_CFG_PATH=${PROJECT_ROOT}/config/" >> ~/.bashrc
    log "PATH added to ~/.bashrc"
fi

export PATH="${PROJECT_ROOT}/bin:$PATH"
export FABRIC_CFG_PATH="${PROJECT_ROOT}/config/"

# تثبيت Fabric binaries في /usr/local/bin لضمان الإرث في كل subprocess
sudo ln -sf "${PROJECT_ROOT}/bin/peer" /usr/local/bin/peer
sudo ln -sf "${PROJECT_ROOT}/bin/configtxgen" /usr/local/bin/configtxgen
sudo ln -sf "${PROJECT_ROOT}/bin/configtxlator" /usr/local/bin/configtxlator
sudo ln -sf "${PROJECT_ROOT}/bin/orderer" /usr/local/bin/orderer 2>/dev/null || true

log "Fabric binaries linked to /usr/local/bin"

# ─── الإصلاح 4: أدوات النظام (المشكلة 11) ───────────────────────────────────
info "Fix 4: Checking required system tools..."

MISSING_TOOLS=()
for tool in jq docker curl wget; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    warn "Installing missing tools: ${MISSING_TOOLS[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${MISSING_TOOLS[@]}"
fi

log "All system tools present: jq=$(jq --version), docker=$(docker --version | head -c 20)..."

# ─── الإصلاح 5: package.json في caliper-workspace (المشكلة 1 و 2) ────────────
info "Fix 5: Setting up caliper-workspace package.json..."

CALIPER_DIR="${PROJECT_ROOT}/caliper-workspace"
mkdir -p "${CALIPER_DIR}"

if [ ! -f "${CALIPER_DIR}/package.json" ]; then
    cat > "${CALIPER_DIR}/package.json" << 'PKGJSON'
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
    log "package.json created"
else
    log "package.json already exists"
fi

# ─── الإصلاح 6: تثبيت Caliper (المشكلة 1 و 6) ───────────────────────────────
info "Fix 6: Installing Caliper dependencies..."

cd "${CALIPER_DIR}"

if [ -d "node_modules" ]; then
    # حذف fabric-network المتعارضة (المشكلة 6)
    if [ -d "node_modules/fabric-network" ]; then
        warn "Removing conflicting fabric-network..."
        rm -rf node_modules/fabric-network node_modules/fabric-common node_modules/fabric-ca-client
    fi
else
    npm install --legacy-peer-deps 2>&1 | tee -a "$LOG_FILE"
fi

# تثبيت blake3 بدون رقم إصدار (المشكلة 2)
if [ ! -d "node_modules/blake3" ]; then
    info "Installing blake3..."
    npm install blake3 --ignore-scripts --legacy-peer-deps 2>&1 | tee -a "$LOG_FILE" || \
        warn "blake3 native unavailable — SHA-256 fallback will be used"
fi

# Bind Caliper to Fabric 2.5
if [ ! -d "node_modules/@hyperledger/fabric-gateway" ]; then
    info "Binding Caliper to Fabric 2.5..."
    npx caliper bind --caliper-bind-sut fabric:2.5 --legacy-peer-deps 2>&1 | tee -a "$LOG_FILE"
fi

log "Caliper setup complete — version: $(npx caliper --version 2>/dev/null | tail -1)"

# ─── الإصلاح 7: إنشاء connection profiles (المشكلة 10) ──────────────────────
info "Fix 7: Creating connection profiles..."

mkdir -p "${CALIPER_DIR}/networks"

cat > "${CALIPER_DIR}/networks/connection-org1.yaml" << 'CONNEOF'
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
      path: /mnt/c/Users/USERW/pro1/fabricNew/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
CONNEOF

cat > "${CALIPER_DIR}/networks/connection-org2.yaml" << 'CONNEOF'
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
      path: /mnt/c/Users/USERW/pro1/fabricNew/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
CONNEOF

log "Connection profiles created"

# ─── الإصلاح 8: issueCertificate.js (المشكلة 7 و 8) ─────────────────────────
info "Fix 8: Checking workload files for crypto.createHash issue..."

WORKLOAD_FILE="${CALIPER_DIR}/workload/issueCertificate.js"
if [ -f "$WORKLOAD_FILE" ]; then
    if grep -q "crypto\.createHash" "$WORKLOAD_FILE"; then
        warn "Found crypto.createHash in issueCertificate.js — fixing..."
        sed -i 's/const certHash = crypto\.createHash.*$/const certHash = blake3Hasher(fields);/' "$WORKLOAD_FILE"
        log "issueCertificate.js fixed"
    else
        log "issueCertificate.js is clean"
    fi
fi

# ─── التحقق النهائي ───────────────────────────────────────────────────────────
echo "" | tee -a "$LOG_FILE"
echo "============================================" | tee -a "$LOG_FILE"
log "All fixes applied successfully"
echo "============================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

info "Verification summary:"
echo "  peer:    $(peer version 2>/dev/null | grep Version | head -1)" | tee -a "$LOG_FILE"
echo "  jq:      $(jq --version)" | tee -a "$LOG_FILE"
echo "  node:    $(node --version)" | tee -a "$LOG_FILE"
echo "  docker:  $(docker --version | head -c 30)..." | tee -a "$LOG_FILE"
echo "  caliper: $(cd ${CALIPER_DIR} && npx caliper --version 2>/dev/null | tail -1)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

log "Setup complete! You can now run: ./run_blake3.sh"
echo "Log saved to: ${LOG_FILE}" | tee -a "$LOG_FILE"
# استبدال أي مسار قديم تلقائياً
find "${CALIPER_DIR}/networks" -type f -name "*.yaml" \
    -exec sed -i "s|/workspaces/fabricNew|${ABS_ROOT}|g" {} \;