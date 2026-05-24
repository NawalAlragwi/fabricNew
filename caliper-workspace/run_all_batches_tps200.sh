#!/bin/bash
# Script to run S4 Hybrid-Batch 5 times (Batch sizes: 10, 15, 20, 25, 30) at TPS 200
# Reports are saved mimicking the past scenario mechanism

export NODE_OPTIONS="--max-old-space-size=8192"

BATCHES=(10 15 20 25 30)

for b in "${BATCHES[@]}"; do
    echo -e "\n\n============================================="
    echo "  Running Scenario 4 - TPS 200 - Batch Size $b"
    echo "============================================="
    
    # Determine the configuration file based on batch size
    if [ "$b" -eq 10 ]; then
        CONFIG="All_benchmarks/hybrid-batch/bcms-s-hybrid-batch-tps200.yaml"
    else
        CONFIG="All_benchmarks/hybrid-batch/bcms-s-hybrid-batch${b}-tps200.yaml"
    fi
    
    # Run Caliper Benchmark
    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig "$CONFIG" \
        --caliper-flow-only-test \
        --caliper-fabric-gateway-enabled
        
    # Define output directory mimicking previous mechanisms (e.g. results/40run_M4/...)
    OUT_DIR="../results/40run_M4/tps200/batch${b}"
    
    # Create the directory
    mkdir -p "$OUT_DIR"
    
    # Move and rename the report
    if [ -f report.html ]; then
        mv report.html "$OUT_DIR/caliper_raw_report.html"
        echo "✅ Report for Batch $b saved successfully to: $OUT_DIR/caliper_raw_report.html"
    else
        echo "❌ ERROR: report.html was not generated for Batch $b."
    fi
    
    # Small pause between runs to let the network stabilize
    sleep 5
done

echo -e "\n============================================="
echo " 🎉 All 5 Batch scenarios for TPS 200 completed successfully!"
echo "============================================="
