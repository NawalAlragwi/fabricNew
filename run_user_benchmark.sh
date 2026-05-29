#!/bin/bash
set -e

cd /mnt/c/Users/USERW/pro1/fabricNew

echo "Redeploying bcms-blake3 (with AVX2)..."
bash redeploy_blake3.sh

echo "Fixing networkConfig.yaml keys..."
bash fix_network_config.sh

echo "Setting contract ID to bcms-blake3 in networkConfig.yaml..."
cd caliper-workspace
sed -i 's/bcms-sha256/bcms-blake3/g' networks/networkConfig.yaml
grep "bcms" networks/networkConfig.yaml

echo "Running Caliper benchmark (BLAKE3 @ 200 TPS)..."
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-benchconfig All_benchmarks/blake3/bcms-s-blake3-tps200.yaml \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-timeout-invokeorquery 120000

mkdir -p reports
cp report.html reports/blake3-tps200-final.html
echo "✓ Benchmark completed! Report saved to reports/blake3-tps200-final.html"
