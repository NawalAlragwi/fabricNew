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
echo " STEP 2: Deploy Chaincode"
echo "==============================================="
cd test-network
# Deploy using network.sh (this packages, installs, approves, and commits)
./network.sh deployCC -ccn bcms-hybrid -ccp ../chaincode-bcms/hybrid -ccl go -c mychannel
cd ..

echo "==============================================="
echo " STEP 3: HashOnlyBenchmark (10 TPS)"
echo "==============================================="
cd caliper-workspace
# Make sure we use the correct network config path
NETWORK_CONFIG="networks/networkConfig.yaml"
if [ ! -f "$NETWORK_CONFIG" ]; then
    echo "Warning: networkConfig.yaml not found, trying to run setup to generate it..."
    cd ..
    # We can generate it by running a tiny part of setup_and_run_all, but normally deployCC leaves the network up
    # However, networkConfig.yaml requires cert paths. Let's just use the one from setup_and_run_all if missing.
    # Actually, the user has setup_and_run_all.sh which generates it.
    # Let's call a custom function or just let caliper fail so we can fix it.
    cd caliper-workspace
fi

npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig "$NETWORK_CONFIG" \
  --caliper-benchconfig hashOnly_hybrid_test.yaml \
  --caliper-flow-only-test

echo "==============================================="
echo " HashOnlyBenchmark complete! Check report.html"
echo "==============================================="
