#!/bin/bash
# Script to run S4 Hybrid-Batch (Batch Size 10) 5 times at TPS 200

export NODE_OPTIONS="--max-old-space-size=8192"

for i in {1..5}; do
    echo -e "\n\n============================================="
    echo "  Running Scenario 4 - TPS 200 (Batch 10) - Run $i/5"
    echo "============================================="
    
    CONFIG="All_benchmarks/hybrid-batch/bcms-s-hybrid-batch-tps200.yaml"
    
    # Run Caliper Benchmark
    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig "$CONFIG" \
        --caliper-flow-only-test \
        --caliper-fabric-gateway-enabled
        
    # Define output directory for each run
    OUT_DIR="../results/40run_M4/tps200/run${i}"
    
    # Create the directory
    mkdir -p "$OUT_DIR"
    
    # Move and rename the report
    if [ -f report.html ]; then
        mv report.html "$OUT_DIR/caliper_raw_report.html"
        echo "✅ Report for Run $i saved successfully to: $OUT_DIR/caliper_raw_report.html"
    else
        echo "❌ ERROR: report.html was not generated for Run $i."
    fi
    
    # Small pause between runs to let the network stabilize
    sleep 5
done

echo -e "\n============================================="
echo " 🎉 All 5 repetitions for TPS 200 completed successfully!"
echo "============================================="
