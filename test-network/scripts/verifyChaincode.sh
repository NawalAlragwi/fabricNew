#!/bin/bash
# ============================================================================
#  Chaincode Verification Script
#  Verifies that chaincode is properly installed and functional
# ============================================================================

source scripts/utils.sh

CHANNEL_NAME="${1:-mychannel}"
CC_NAME="${2:-basic}"

println ""
println "════════════════════════════════════════════════════════════════"
println "  Chaincode Verification: $CC_NAME on channel: $CHANNEL_NAME"
println "════════════════════════════════════════════════════════════════"
println ""

# Load environment
. scripts/envVar.sh
setGlobals 1

infoln "1️⃣  Checking package file..."
if [ -f "${CC_NAME}.tar.gz" ]; then
    successln "   ✓ Package file exists: ${CC_NAME}.tar.gz"
    ls -lh ${CC_NAME}.tar.gz | sed 's/^/     /'
else
    errorln "   ❌ Package file not found: ${CC_NAME}.tar.gz"
fi
println ""

infoln "2️⃣  Calculating package ID..."
if [ -f "${CC_NAME}.tar.gz" ]; then
    PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)
    successln "   ✓ Package ID: $PACKAGE_ID"
else
    errorln "   ❌ Cannot calculate package ID - file not found"
fi
println ""

infoln "3️⃣  Checking installed chaincodes on peer0.org1..."
peer lifecycle chaincode queryinstalled --output json | jq . | sed 's/^/     /'
println ""

infoln "4️⃣  Checking committed chaincodes on channel..."
peer lifecycle chaincode querycommitted -C $CHANNEL_NAME --output json | jq . | sed 's/^/     /'
println ""

infoln "5️⃣  Testing chaincode invocation..."
set -x
peer chaincode query \
    -C $CHANNEL_NAME \
    -n $CC_NAME \
    -c '{"function":"GetAllAssets","Args":[]}' \
    2>&1 | head -20
{ set +x; } 2>/dev/null
println ""

successln "✅ Chaincode verification complete"
