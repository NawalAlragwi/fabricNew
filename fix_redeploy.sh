#!/bin/bash
# ============================================================================
# fix_redeploy.sh — Redeploy bcms-sha256 without compiled binaries
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

export PATH="${ROOT_DIR}/bin:$PATH"
export FABRIC_CFG_PATH="${ROOT_DIR}/config/"
export GOFLAGS="-mod=mod"
export GOWORK="off"
export GO111MODULE="on"
export GOAMD64="v3"
export GOPROXY="https://proxy.golang.org,direct"

echo "============================================================"
echo "  Step 1: Removing old chaincode images and tar.gz"
echo "============================================================"
OLD_IMGS=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "dev-peer.*bcms-sha256" || true)
if [ -n "$OLD_IMGS" ]; then
    echo "$OLD_IMGS" | while read img; do
        docker rmi -f "$img" 2>/dev/null && echo "  Removed: $img" || true
    done
fi
rm -f "${ROOT_DIR}/test-network/bcms-sha256.tar.gz"
echo "  Done."

echo "============================================================"
echo "  Step 2: Verifying no binaries in chaincode source"
echo "============================================================"
ls -la "${ROOT_DIR}/chaincode-bcms/sha256/" | grep -v ".go\|vendor\|META\|go.mod\|go.sum\|.gitignore" || echo "  Clean!"

echo "============================================================"
echo "  Step 3: Deploying chaincode bcms-sha256"
echo "============================================================"
cd "${ROOT_DIR}/test-network"
./network.sh deployCC \
    -ccn "bcms-sha256" \
    -ccp "${ROOT_DIR}/chaincode-bcms/sha256" \
    -ccl go \
    -c mychannel \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

echo "============================================================"
echo "  Step 4: Waiting for Docker image to be built (warm-up)"
echo "============================================================"
cd "${ROOT_DIR}"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

MAX=15
attempt=1
while [ $attempt -le $MAX ]; do
    echo "  Warm-up attempt ${attempt}/${MAX}..."
    result=$(peer chaincode query -C mychannel -n bcms-sha256 \
        -c '{"Args":["QueryAllCertificates","5",""]}' 2>&1) && {
        echo "  ✓ Chaincode is LIVE! Response received."
        echo "$result"
        break
    }
    echo "  Not ready yet: ${result:0:120}"
    sleep 10
    attempt=$((attempt + 1))
done

[ $attempt -gt $MAX ] && echo "ERROR: Chaincode still not ready after ${MAX} attempts!" && exit 1

echo ""
echo "  ✓ bcms-sha256 chaincode is running correctly!"
echo "  You can now run: bash setup_and_run_all.sh --scenario=1 --skip-network"
