#!/bin/bash
set -euo pipefail

echo "============================================="
echo "  1. Setting up Fabric Network & Chaincode (Scenario 4)"
echo "============================================="
cd /mnt/c/Users/USERW/pro1/fabricNew
bash setup_and_run_all.sh --scenario=4 --tps=100 --skip-caliper --skip-tamarin

echo "============================================="
echo "  2. Running Custom Caliper Benchmark"
echo "     Issue TPS: 15, verify: linear 20->100"
echo "     totalIssued: 900, batchSize: 5"
echo "============================================="
cd caliper-workspace
export NODE_OPTIONS="--max-old-space-size=8192"
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig All_benchmarks/hybrid-batch/bcms-s-hybrid-batch5-custom.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

# Move report to a specific directory so it is saved
mkdir -p ../results/custom_run
mv report.html ../results/custom_run/caliper_raw_report.html

echo "============================================="
echo " ✅ Test Completed. Report saved to: results/custom_run/caliper_raw_report.html"
echo "============================================="
