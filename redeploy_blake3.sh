#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

export PATH="${ROOT_DIR}/bin:$PATH"
export FABRIC_CFG_PATH="${ROOT_DIR}/config/"
export GOFLAGS="-mod=mod"
export GOWORK="off"
export GO111MODULE="on"
export GOAMD64="v3"

echo "============================================================"
echo "  Deploying chaincode bcms-blake3"
echo "============================================================"
cd "${ROOT_DIR}/test-network"

# Remove old containers if they exist to prevent caching issues
OLD_IMGS=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "dev-peer.*bcms-blake3" || true)
if [ -n "$OLD_IMGS" ]; then
    echo "$OLD_IMGS" | while read img; do
        docker rmi -f "$img" 2>/dev/null || true
    done
fi
rm -f "${ROOT_DIR}/test-network/bcms-blake3.tar.gz"

./network.sh deployCC \
    -ccn "bcms-blake3" \
    -ccp "../chaincode-bcms/blake3" \
    -ccl go \
    -c mychannel \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

echo "============================================================"
echo "  Waiting for Docker image to be built (warm-up)"
echo "============================================================"
cd "${ROOT_DIR}"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

# Initialize the ledger
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "${ROOT_DIR}/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem" -C mychannel -n bcms-blake3 --peerAddresses localhost:7051 --tlsRootCertFiles "${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" --peerAddresses localhost:9051 --tlsRootCertFiles "${ROOT_DIR}/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt" -c '{"function":"InitLedger","Args":[]}'

sleep 5

MAX=15
attempt=1
while [ $attempt -le $MAX ]; do
    echo "  Warm-up attempt ${attempt}/${MAX}..."
    result=$(peer chaincode query -C mychannel -n bcms-blake3 \
        -c '{"Args":["QueryAllCertificates","5",""]}' 2>&1) && {
        echo "  ✓ Chaincode is LIVE! Response received."
        echo "$result"
        break
    }
    echo "  Not ready yet: ${result:0:120}"
    sleep 5
    attempt=$((attempt + 1))
done

[ $attempt -gt $MAX ] && echo "ERROR: Chaincode still not ready after ${MAX} attempts!" && exit 1
echo "  ✓ bcms-blake3 chaincode is running correctly!"
