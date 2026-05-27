#!/bin/bash
# Script to run S4 Hybrid-Batch at TPS 200 with Batch size 5

export NODE_OPTIONS="--max-old-space-size=8192"

echo -e "\n\n============================================="
echo "  Running Scenario 4 - TPS 200 - Batch Size 5"
echo "============================================="

CONFIG="All_benchmarks/hybrid-batch/bcms-s-hybrid-batch5-tps200.yaml"

# Run Caliper Benchmark
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig "$CONFIG" \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled
    
OUT_DIR="../results/40run_M4/tps200/batch5"

# Create the directory
mkdir -p "$OUT_DIR"

# Move and rename the report
if [ -f report.html ]; then
    mv report.html "$OUT_DIR/caliper_raw_report.html"
    echo "✅ Report for Batch 5 saved successfully to: $OUT_DIR/caliper_raw_report.html"
else
    echo "❌ ERROR: report.html was not generated for Batch 5."
fi

echo -e "\n============================================="
echo " 🎉 Batch 5 scenario for TPS 200 completed successfully!"
echo "============================================="
