#!/bin/bash
set -e

echo "============================================================"
echo "  Automated Caliper Fix and Run Script v3.0"
echo "  Fixed: Dynamic ROOT_DIR, path resolution, bind version,"
echo "         connection profile generation, report cleanup,"
echo "         custom PhD-level report post-processing"
echo "============================================================"

# ============================================================
# 1. SETUP: Auto-detect ROOT_DIR (no hardcoded paths!)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Auto-detected ROOT_DIR: $ROOT_DIR"

if [ ! -d "$ROOT_DIR/test-network" ]; then
    echo "ERROR: test-network directory not found at $ROOT_DIR/test-network"
    echo "Please run this script from inside the caliper-workspace directory"
    echo "or ensure the repository structure is intact."
    exit 1
fi

echo "ROOT_DIR verified: $ROOT_DIR"

# Change to caliper-workspace directory
cd "$SCRIPT_DIR"
echo "Working directory: $(pwd)"

# Create necessary directories
mkdir -p workload benchmarks networks

# ============================================================
# 1.5 CLEANUP: Remove old reports to expose failures
# ============================================================
echo "Cleaning up old reports and logs..."
rm -f report.html
rm -f report_custom.html
rm -f caliper.log
echo "Old reports removed. Fresh reports will be generated."

# ============================================================
# 2. DYNAMIC KEY FINDING: Locate private keys for BOTH orgs
# ============================================================
echo "Searching for private keys..."

# Org1 Key
KEY_DIR1="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY1=$(find "$KEY_DIR1" -name "*_sk" -type f 2>/dev/null | head -n 1)

if [ -z "$PVT_KEY1" ] || [ ! -f "$PVT_KEY1" ]; then
    echo "ERROR: Org1 private key not found in $KEY_DIR1"
    echo "Ensure the Fabric network is running with CA enabled."
    exit 1
fi
echo "Org1 Private Key Found: $PVT_KEY1"

# Org1 Certificate - try both naming conventions
CERT_DIR1="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts"
if [ -f "$CERT_DIR1/User1@org1.example.com-cert.pem" ]; then
    CERT_FILE1="$CERT_DIR1/User1@org1.example.com-cert.pem"
elif [ -f "$CERT_DIR1/cert.pem" ]; then
    CERT_FILE1="$CERT_DIR1/cert.pem"
else
    CERT_FILE1=$(find "$CERT_DIR1" -name "*.pem" -type f 2>/dev/null | head -n 1)
    if [ -z "$CERT_FILE1" ]; then
        echo "ERROR: Org1 certificate not found in $CERT_DIR1"
        exit 1
    fi
fi
echo "Org1 Certificate Found: $CERT_FILE1"

# Org2 Key
KEY_DIR2="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
PVT_KEY2=$(find "$KEY_DIR2" -name "*_sk" -type f 2>/dev/null | head -n 1)

if [ -z "$PVT_KEY2" ] || [ ! -f "$PVT_KEY2" ]; then
    echo "ERROR: Org2 private key not found in $KEY_DIR2"
    echo "Ensure the Fabric network is running with CA enabled."
    exit 1
fi
echo "Org2 Private Key Found: $PVT_KEY2"

# Org2 Certificate - try both naming conventions
CERT_DIR2="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts"
if [ -f "$CERT_DIR2/User1@org2.example.com-cert.pem" ]; then
    CERT_FILE2="$CERT_DIR2/User1@org2.example.com-cert.pem"
elif [ -f "$CERT_DIR2/cert.pem" ]; then
    CERT_FILE2="$CERT_DIR2/cert.pem"
else
    CERT_FILE2=$(find "$CERT_DIR2" -name "*.pem" -type f 2>/dev/null | head -n 1)
    if [ -z "$CERT_FILE2" ]; then
        echo "ERROR: Org2 certificate not found in $CERT_DIR2"
        exit 1
    fi
fi
echo "Org2 Certificate Found: $CERT_FILE2"

# ============================================================
# 3. TLS Certificate paths for connection profile
# ============================================================
ORDERER_TLS="$ROOT_DIR/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
PEER0_ORG1_TLS="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
PEER0_ORG2_TLS="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
CA_ORG1_CERT="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem"
CA_ORG2_CERT="$ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem"

# Verify TLS certs exist
for f in "$ORDERER_TLS" "$PEER0_ORG1_TLS" "$PEER0_ORG2_TLS"; do
    if [ ! -f "$f" ]; then
        echo "WARNING: TLS certificate not found: $f"
    fi
done

# ============================================================
# 4. GENERATE NETWORK CONFIG (with both Org1 and Org2 identities)
# ============================================================
echo "Generating networks/networkConfig.yaml..."

cat > networks/networkConfig.yaml << NETWORK_EOF
name: Caliper-Fabric
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
NETWORK_EOF

echo "Network config created."

# ============================================================
# 5. GENERATE CONNECTION PROFILE for Org1
# ============================================================
echo "Generating networks/connection-org1.yaml..."

cat > networks/connection-org1.yaml << CONNECTION_EOF
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
CONNECTION_EOF

echo "Connection profile for Org1 created."

# ============================================================
# 5.5 GENERATE CONNECTION PROFILE for Org2
# ============================================================
echo "Generating networks/connection-org2.yaml..."

cat > networks/connection-org2.yaml << CONNECTION_EOF
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
CONNECTION_EOF

echo "Connection profile for Org2 created."

# ============================================================
# 6. INSTALL DEPENDENCIES AND BIND CALIPER
# ============================================================
echo "Installing Caliper dependencies..."

npm install --silent 2>/dev/null || npm install

echo "Binding Caliper to Fabric 2.5 (matching network version)..."

npx caliper bind --caliper-bind-sut fabric:2.5 --caliper-bind-args=-g

# ============================================================
# 7. WAIT for network readiness
# ============================================================
echo "Waiting 10 seconds for network stabilization..."
sleep 10

# ============================================================
# 8. RUN CALIPER BENCHMARK
# ============================================================
echo "============================================================"
echo "  Launching Caliper Benchmark (4 rounds)"
echo "  Round 1: IssueCertificate     @ 50 TPS  / 30s"
echo "  Round 2: VerifyCertificate    @ 100 TPS / 30s"
echo "  Round 3: QueryAllCertificates @ 50 TPS  / 30s"
echo "  Round 4: RevokeCertificate    @ 50 TPS  / 30s"
echo "============================================================"

npx caliper launch manager \
  --caliper-workspace ./ \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-benchconfig benchmarks/benchConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled

# ============================================================
# 9. VERIFY DEFAULT REPORT AND GENERATE CUSTOM REPORT
# ============================================================
if [ -f "report.html" ]; then
    REPORT_SIZE=$(stat -c%s "report.html" 2>/dev/null || stat -f%z "report.html" 2>/dev/null)
    echo ""
    echo "============================================================"
    echo "  DEFAULT CALIPER REPORT GENERATED"
    echo "  Report: $(pwd)/report.html ($REPORT_SIZE bytes)"
    echo "============================================================"

    # ── Run Custom Report Post-Processor ──
    echo ""
    echo "============================================================"
    echo "  Running Custom Report Post-Processor (PhD-Level)"
    echo "============================================================"

    if [ -f "generate_custom_report.js" ]; then
        node generate_custom_report.js report.html report_custom.html
        if [ -f "report_custom.html" ]; then
            CUSTOM_SIZE=$(stat -c%s "report_custom.html" 2>/dev/null || stat -f%z "report_custom.html" 2>/dev/null)
            echo ""
            echo "============================================================"
            echo "  BENCHMARK COMPLETE — BOTH REPORTS GENERATED"
            echo "  Default Report: $(pwd)/report.html ($REPORT_SIZE bytes)"
            echo "  Custom Report:  $(pwd)/report_custom.html ($CUSTOM_SIZE bytes)"
            echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "============================================================"
        else
            echo "WARNING: Custom report generation failed."
            echo "Default report is still available: $(pwd)/report.html"
        fi
    else
        echo "WARNING: generate_custom_report.js not found."
        echo "Default report: $(pwd)/report.html ($REPORT_SIZE bytes)"
    fi
else
    echo ""
    echo "ERROR: report.html was NOT generated!"
    echo "Check caliper.log for errors."
    echo "Common issues:"
    echo "  - Network not running (docker ps)"
    echo "  - Chaincode not deployed"
    echo "  - Certificate path mismatch"
    exit 1
fi
