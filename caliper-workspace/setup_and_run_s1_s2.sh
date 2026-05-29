#!/bin/bash
# ============================================================================
#  BCMS — Automated S1 + S2 Benchmark Runner v5.0
#  FIX-#2: ينشر bcms-sha256 و bcms-blake3 كـ chaincodes منفصلة
#  FIX-#3: TPS مرتفع (200 fixed + 500→1500 linear) لإظهار فرق الـ CPU
#
#  الترتيب:
#    1. فحص الشبكة
#    2. نشر bcms-sha256  (chaincode-bcms/sha256)
#    3. تشغيل S1 (SHA-256 benchmark)
#    4. نشر bcms-blake3  (chaincode-bcms/blake3)
#    5. تشغيل S2 (BLAKE3 benchmark)
#    6. توليد التقارير المقارنة
#
#  Usage:
#    bash setup_and_run_s1_s2.sh [--skip-deploy] [--s1-only] [--s2-only]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_NET="$ROOT_DIR/test-network"
CHAINCODE_SHA256="$ROOT_DIR/chaincode-bcms/sha256"
CHAINCODE_BLAKE3="$ROOT_DIR/chaincode-bcms/blake3"
CALIPER_DIR="$SCRIPT_DIR"

# ── Options ───────────────────────────────────────────────────────────────────
SKIP_DEPLOY=false
S1_ONLY=false
S2_ONLY=false
for arg in "$@"; do
    case $arg in
        --skip-deploy) SKIP_DEPLOY=true ;;
        --s1-only)     S1_ONLY=true ;;
        --s2-only)     S2_ONLY=true ;;
    esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}══════════════════════════════════════════════${NC}"; \
          echo -e "${CYAN}  $1${NC}"; \
          echo -e "${CYAN}══════════════════════════════════════════════${NC}"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  BCMS Benchmark Runner v5.0 — S1(SHA-256) + S2(BLAKE3)     ║"
echo "║  FIX-#2: Isolated chaincodes | FIX-#3: High TPS            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 0: فحص أن الشبكة تعمل ───────────────────────────────────────────────
step "Checking Fabric Network"
if ! docker ps --filter "name=peer0.org1.example.com" --filter "status=running" | grep -q peer0; then
    error "peer0.org1.example.com is not running. Start network first:\n  cd test-network && ./network.sh up createChannel -c mychannel -ca -s couchdb"
fi
info "✓ Fabric network is running"

# ── Step 1: تحديد مسارات المفاتيح ────────────────────────────────────────────
step "Locating Cryptographic Material"

KEY_DIR1="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY1=$(find "$KEY_DIR1" -type f 2>/dev/null | head -n 1)
[ -z "$PVT_KEY1" ] && error "Org1 private key not found in $KEY_DIR1"
info "✓ Org1 Key: $(basename $PVT_KEY1)"

CERT_DIR1="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts"
CERT_FILE1=$(find "$CERT_DIR1" -name "*.pem" -o -name "cert.pem" 2>/dev/null | head -n 1)
[ -z "$CERT_FILE1" ] && CERT_FILE1=$(find "$CERT_DIR1" -type f 2>/dev/null | head -n 1)
[ -z "$CERT_FILE1" ] && error "Org1 certificate not found"
info "✓ Org1 Cert: $(basename $CERT_FILE1)"

KEY_DIR2="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
PVT_KEY2=$(find "$KEY_DIR2" -type f 2>/dev/null | head -n 1)
[ -z "$PVT_KEY2" ] && error "Org2 private key not found"
info "✓ Org2 Key: $(basename $PVT_KEY2)"

CERT_DIR2="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts"
CERT_FILE2=$(find "$CERT_DIR2" -name "*.pem" -o -name "cert.pem" 2>/dev/null | head -n 1)
[ -z "$CERT_FILE2" ] && CERT_FILE2=$(find "$CERT_DIR2" -type f 2>/dev/null | head -n 1)
[ -z "$CERT_FILE2" ] && error "Org2 certificate not found"
info "✓ Org2 Cert: $(basename $CERT_FILE2)"

# TLS paths
ORDERER_TLS="$ROOT_DIR/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
PEER0_ORG1_TLS="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
PEER0_ORG2_TLS="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
CA_ORG1_CERT="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem"
CA_ORG2_CERT="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem"

# ── Step 2: توليد networkConfig ──────────────────────────────────────────────
step "Generating Network Config"
mkdir -p "$CALIPER_DIR/networks" "$CALIPER_DIR/logs"

cat > "$CALIPER_DIR/networks/networkConfig.yaml" << NETWORK_EOF
name: bcms-test-network
version: "2.0.0"

caliper:
  blockchain: fabric

channels:
  - channelName: mychannel
    contracts:
      - id: bcms-sha256
      - id: bcms-blake3

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
NETWORK_EOF
info "✓ networkConfig.yaml generated (bcms-sha256 + bcms-blake3)"

# ── توليد connection profiles ──────────────────────────────────────────────────
cat > "$CALIPER_DIR/networks/connection-org1.yaml" << CONN_EOF
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
        eventSource: false

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
      path: $ORDERER_TLS

peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
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
  ca.org1.example.com:
    url: https://localhost:7054
    caName: ca-org1
    tlsCACerts:
      path: $CA_ORG1_CERT
    httpOptions:
      verify: false
CONN_EOF

cat > "$CALIPER_DIR/networks/connection-org2.yaml" << CONN_EOF
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
        eventSource: false
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
CONN_EOF
info "✓ Connection profiles generated"

# ── دالة نشر chaincode ────────────────────────────────────────────────────────
deploy_chaincode() {
    local CC_NAME="$1"
    local CC_PATH="$2"

    step "Deploying Chaincode: $CC_NAME"
    info "Path: $CC_PATH"

    # التحقق من الترجمة
    info "Verifying Go compilation..."
    cd "$CC_PATH"
    go build ./... || error "Compilation failed for $CC_NAME"
    cd "$TEST_NET"
    info "✓ $CC_NAME compiled successfully"

    # التحقق إن كان منشوراً بالفعل
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE="$TEST_NET/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="$TEST_NET/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
    export CORE_PEER_ADDRESS=localhost:7051
    export ORDERER_CA="$TEST_NET/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

    if peer chaincode query -C mychannel -n "$CC_NAME" -c '{"function":"GetHashAlgorithm","Args":[]}' 2>/dev/null | grep -q .; then
        info "✓ $CC_NAME is already deployed and responding — skipping redeploy"
        cd "$CALIPER_DIR"
        return 0
    fi

    # نشر الـ chaincode
    info "Deploying $CC_NAME on mychannel..."
    ./network.sh deployCC \
        -ccn "$CC_NAME" \
        -ccp "$CC_PATH" \
        -ccl go \
        -c mychannel \
        -ccep "OR('Org1MSP.peer','Org2MSP.peer')" \
        -cccg "OR('Org1MSP.peer','Org2MSP.peer')"
    info "✓ $CC_NAME deployed"

    # تهيئة الـ ledger
    info "Initializing ledger for $CC_NAME..."
    sleep 5
    peer chaincode invoke \
        -o localhost:7050 \
        --ordererTLSHostnameOverride orderer.example.com \
        --tls --cafile "$ORDERER_CA" \
        -C mychannel -n "$CC_NAME" \
        --peerAddresses localhost:7051 \
        --tlsRootCertFiles "$TEST_NET/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" \
        --peerAddresses localhost:9051 \
        --tlsRootCertFiles "$TEST_NET/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt" \
        -c '{"function":"InitLedger","Args":[]}' \
        --waitForEvent
    info "✓ $CC_NAME ledger initialized"

    cd "$CALIPER_DIR"
}

# ── Step 3: نشر الـ chaincodes ───────────────────────────────────────────────
if [ "$SKIP_DEPLOY" = false ]; then
    cd "$TEST_NET"
    if [ "$S2_ONLY" = false ]; then
        deploy_chaincode "bcms-sha256" "$CHAINCODE_SHA256"
    fi
    if [ "$S1_ONLY" = false ]; then
        deploy_chaincode "bcms-blake3" "$CHAINCODE_BLAKE3"
    fi
    cd "$CALIPER_DIR"
else
    warn "Skipping chaincode deployment (--skip-deploy)"
fi

# ── Step 4: تثبيت Caliper ──────────────────────────────────────────────────────
step "Installing Caliper Dependencies"
cd "$CALIPER_DIR"
npm install --silent 2>/dev/null || npm install
npx caliper bind --caliper-bind-sut fabric:2.5 --caliper-bind-args=-g 2>&1 | tail -3
info "✓ Caliper bound to Fabric 2.5"

# ── Step 5: تشغيل S1 (SHA-256) ───────────────────────────────────────────────
if [ "$S2_ONLY" = false ]; then
    step "Running S1 — SHA-256 Benchmark (bcms-sha256)"
    echo "  IssueCertificate  : 200 TPS fixed-rate   × 120s"
    echo "  VerifyCertificate : 500→1500 TPS linear  × 120s  ← KEY ROUND"
    echo "  QueryAll          : 20 TPS fixed-rate    × 120s"
    echo "  RevokeCertificate : 100→500 TPS linear   × 120s"
    echo ""

    sleep 10  # استقرار الشبكة

    npx caliper launch manager \
        --caliper-workspace "$CALIPER_DIR" \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig benchmarks/benchConfig_s1_sha256.yaml \
        --caliper-flow-only-test \
        --caliper-fabric-gateway-enabled \
        --caliper-report-path report_S1_SHA256.html \
        2>&1 | tee "$CALIPER_DIR/logs/s1_sha256_$(date +%Y%m%d_%H%M%S).log"

    # نسخ التقرير
    [ -f "report.html" ] && cp report.html report_S1_SHA256.html && info "✓ S1 report saved: report_S1_SHA256.html"

    info "✓ S1 (SHA-256) benchmark complete — waiting 30s before S2..."
    sleep 30
fi

# ── Step 6: تشغيل S2 (BLAKE3) ────────────────────────────────────────────────
if [ "$S1_ONLY" = false ]; then
    step "Running S2 — BLAKE3 Benchmark (bcms-blake3)"
    echo "  IssueCertificate  : 200 TPS fixed-rate   × 120s"
    echo "  VerifyCertificate : 500→1500 TPS linear  × 120s  ← KEY ROUND"
    echo "  QueryAll          : 20 TPS fixed-rate    × 120s"
    echo "  RevokeCertificate : 100→500 TPS linear   × 120s"
    echo ""

    sleep 10  # استقرار الشبكة

    npx caliper launch manager \
        --caliper-workspace "$CALIPER_DIR" \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig benchmarks/benchConfig_s2_blake3.yaml \
        --caliper-flow-only-test \
        --caliper-fabric-gateway-enabled \
        --caliper-report-path report_S2_BLAKE3.html \
        2>&1 | tee "$CALIPER_DIR/logs/s2_blake3_$(date +%Y%m%d_%H%M%S).log"

    [ -f "report.html" ] && cp report.html report_S2_BLAKE3.html && info "✓ S2 report saved: report_S2_BLAKE3.html"
fi

# ── Step 7: ملخص ──────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              BENCHMARK COMPLETE                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
[ -f "$CALIPER_DIR/report_S1_SHA256.html" ] && \
    echo "║  S1 SHA-256 Report : report_S1_SHA256.html                  ║"
[ -f "$CALIPER_DIR/report_S2_BLAKE3.html" ] && \
    echo "║  S2 BLAKE3  Report : report_S2_BLAKE3.html                  ║"
echo "║  Logs              : caliper-workspace/logs/                 ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  KEY METRIC: VerifyCertificate avg latency                  ║"
echo "║  Expected: BLAKE3 ≈ 3.74x lower latency than SHA-256        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
