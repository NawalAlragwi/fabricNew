#!/bin/bash
# ============================================================================
#  Chaincode Quick Deployment Test
#  Deploys chaincode with detailed diagnostics
# ============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${ROOT_DIR}/chaincode_test_${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
log()   { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; }
info()  { echo -e "${CYAN}[i]${NC} $*" | tee -a "$LOG_FILE"; }
step()  { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}$*${NC}\n" | tee -a "$LOG_FILE"; }

# Banner
echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║  Chaincode Quick Deployment Test                      ║${NC}"
echo -e "${BOLD}${CYAN}║  BCMS - Hybrid Batch (SHA-256 + BLAKE3)               ║${NC}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Log file: $LOG_FILE"
echo ""

# ──── Step 1: Prerequisites Check ────
step "Step 1: Prerequisites Check"

check_command() {
    if command -v "$1" &>/dev/null; then
        log "Found: $1"
        return 0
    else
        error "Not found: $1"
        return 1
    fi
}

MISSING=0
check_command "docker"     || MISSING=1
check_command "docker-compose" || MISSING=1
check_command "go"         || MISSING=1
check_command "node"       || MISSING=1
check_command "npm"        || MISSING=1
check_command "peer"       || warn "peer binary not in PATH (will check in bin/)"

if [ $MISSING -eq 1 ]; then
    error "Some required tools are missing. Please install them."
    exit 1
fi

log "All prerequisites available"

# ──── Step 2: Chaincode Files Check ────
step "Step 2: Chaincode Files Check"

CHAINCODE_DIR="${ROOT_DIR}/chaincode-bcms/hybrid-batch"

check_file() {
    if [ -f "$1" ]; then
        log "Found: $(basename $1)"
        return 0
    else
        error "Missing: $1"
        return 1
    fi
}

MISSING=0
check_file "${CHAINCODE_DIR}/main.go"                 || MISSING=1
check_file "${CHAINCODE_DIR}/smartcontract_hybrid.go" || MISSING=1
check_file "${CHAINCODE_DIR}/go.mod"                  || MISSING=1
check_file "${CHAINCODE_DIR}/go.sum"                  || MISSING=1

if [ $MISSING -eq 1 ]; then
    error "Some chaincode files are missing"
    exit 1
fi

log "All chaincode files present"

# ──── Step 3: Docker Status ────
step "Step 3: Docker Status"

info "Docker is running:"
docker ps --format "table {{.Image}}\t{{.Status}}" 2>&1 | head -5

info "Checking for conflicting containers..."
if docker ps -a | grep -E "basic|chaincode" > /dev/null 2>&1; then
    warn "Found existing chaincode containers - they will be removed"
    docker ps -a | grep -E "basic|chaincode" | awk '{print $1}' | xargs -r docker rm -f || true
fi

log "Docker environment ready"

# ──── Step 4: Network Status ────
step "Step 4: Fabric Network Status"

cd "${ROOT_DIR}/test-network"

info "Checking current network state..."
if docker ps | grep -q "hyperledger"; then
    log "Network containers are running"
else
    warn "Network containers not running - will start them"
fi

# ──── Step 5: Clean and Start Network ────
step "Step 5: Network Startup"

info "Bringing down any existing network..."
./network.sh down 2>&1 | tail -5 | tee -a "$LOG_FILE" || true
docker volume prune -f > /dev/null 2>&1 || true

info "Cleaning old package files..."
rm -f *.tar.gz log.txt

info "Starting fresh Hyperledger Fabric network..."
./network.sh up createChannel -c mychannel -ca -s couchdb 2>&1 | tee -a "$LOG_FILE" || {
    error "Network startup failed"
    exit 1
}

log "Network started successfully"

info "Waiting 30 seconds for network stabilization..."
for i in {30..1}; do
    echo -ne "\r⏳ $i seconds remaining...   "
    sleep 1
done
echo ""

# ──── Step 6: Environment Setup ────
step "Step 6: Environment Configuration"

export GOFLAGS="-mod=mod"
export GOWORK="off"
export GO111MODULE="on"
export FABRIC_CFG_PATH="${ROOT_DIR}/config/"

log "GOFLAGS=$GOFLAGS"
log "GOWORK=$GOWORK"
log "GO111MODULE=$GO111MODULE"
log "FABRIC_CFG_PATH=$FABRIC_CFG_PATH"

# ──── Step 7: Chaincode Deployment ────
step "Step 7: Chaincode Deployment"

info "Deploying BCMS Hybrid-Batch chaincode..."
info "  Name: basic"
info "  Path: ${CHAINCODE_DIR}"
info "  Language: Go"
info "  Channel: mychannel"

./network.sh deployCC \
    -ccn basic \
    -ccp "${CHAINCODE_DIR}" \
    -ccl go \
    -c mychannel \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')" \
    2>&1 | tee -a "$LOG_FILE" || {
    error "Chaincode deployment failed"
    echo ""
    echo -e "${YELLOW}Last 30 lines of error:${NC}"
    tail -30 "$LOG_FILE" | grep -i "error\|failed" || tail -30 "$LOG_FILE"
    exit 1
}

log "Chaincode deployed successfully"

# ──── Step 8: Verification ────
step "Step 8: Deployment Verification"

info "Querying installed chaincodes..."
source "${ROOT_DIR}/test-network/scripts/envVar.sh"
setGlobals 1

INSTALLED=$(peer lifecycle chaincode queryinstalled --output json | jq '.installed_chaincodes[] | select(.label | contains("basic")) | .label' -r)

if [ -n "$INSTALLED" ]; then
    log "Chaincode installed: $INSTALLED"
else
    error "Chaincode not found in installed list"
    exit 1
fi

info "Querying committed chaincodes..."
COMMITTED=$(peer lifecycle chaincode querycommitted -C mychannel --output json | jq '.committed_chaincodes[] | select(.name=="basic") | .name' -r)

if [ "$COMMITTED" = "basic" ]; then
    log "Chaincode committed to channel: mychannel"
else
    error "Chaincode not committed to channel"
    exit 1
fi

# ──── Step 9: Functional Test ────
step "Step 9: Functional Test"

info "Testing chaincode invocation..."
peer chaincode query \
    -C mychannel \
    -n basic \
    -c '{"function":"GetAllAssets","Args":[]}' \
    2>&1 | tee -a "$LOG_FILE"

log "Chaincode is functional"

# ──── Summary ────
step "Test Summary"

echo -e "${BOLD}${GREEN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║                  ✅ ALL TESTS PASSED                   ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║                                                        ║"
echo "║  ✓ Prerequisites verified                             ║"
echo "║  ✓ Chaincode files present                            ║"
echo "║  ✓ Docker ready                                       ║"
echo "║  ✓ Network started                                    ║"
echo "║  ✓ Chaincode packaged and deployed                    ║"
echo "║  ✓ Chaincode installed                                ║"
echo "║  ✓ Chaincode committed                                ║"
echo "║  ✓ Chaincode functional                               ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
info "Log file saved to: $LOG_FILE"
echo ""

exit 0
