#!/bin/bash
# Script to run S3 Hybrid 5 times at TPS 200

export NODE_OPTIONS="--max-old-space-size=8192"

for i in {3..5}; do
    echo -e "\n\n============================================="
    echo "  Running Scenario 3 (Hybrid) - TPS 200 - Run $i/5"
    echo "============================================="
    
    CONFIG="All_benchmarks/hybrid/bcms-s-hybrid-tps200.yaml"
    
    # Run Caliper Benchmark
    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig "$CONFIG" \
        --caliper-flow-only-test \
        --caliper-fabric-gateway-enabled
        
    # Define output directory for each run
    OUT_DIR="../results/30run_M3/tps200/run${i}"
    
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
echo " 🎉 All 5 repetitions for S3 (TPS 200) completed successfully!"
echo "============================================="
