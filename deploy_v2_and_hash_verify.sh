#!/bin/bash
set -e

ROOT_DIR="/mnt/c/Users/USERW/pro1/fabricNew"
cd "$ROOT_DIR" || cd "/c/Users/USERW/pro1/fabricNew" || cd "c:/Users/USERW/pro1/fabricNew"

echo "==============================================="
echo " STEP 1: Build Chaincode"
echo "==============================================="
cd chaincode-bcms/hybrid
go mod tidy
go build ./...
echo "Chaincode built successfully."
cd ../..

echo "==============================================="
echo " STEP 2: Deploy Chaincode (Version 2)"
echo "==============================================="
cd test-network
# Force sequence 2 and version 2.0 to ensure the updated chaincode runs!
./network.sh deployCC -ccn bcms-hybrid -ccp ../chaincode-bcms/hybrid -ccl go -c mychannel -ccs 2 -ccv 2.0
cd ..

echo "==============================================="
echo " STEP 3: HashOnlyBenchmark (10 TPS)"
echo "==============================================="
cd caliper-workspace
NETWORK_CONFIG="networks/networkConfig.yaml"

npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig "$NETWORK_CONFIG" \
  --caliper-benchconfig hashOnly_hybrid_test.yaml \
  --caliper-flow-only-test

echo "==============================================="
echo " HashOnlyBenchmark complete! Check report.html"
echo "==============================================="
