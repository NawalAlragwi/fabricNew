#!/bin/bash
# ============================================================
#  S2 — BLAKE3 | TPS 200 | 2 Runs (Run 6 & Run 7)
#  Benchmark: bcms-s2-blake3-tps200
#  workers: 15 | IssueCertificate: 30 TPS/30s
#  VerifyCertificate: 40->200 TPS (linear) / 30s
# ============================================================

export NODE_OPTIONS="--max-old-space-size=8192"

CONFIG="All_benchmarks/blake3/bcms-s2-blake3-tps200.yaml"
START_RUN=6
END_RUN=7

echo -e "\n============================================="
echo "  S2 BLAKE3 TPS-200 — Runs $START_RUN to $END_RUN"
echo "  Config: $CONFIG"
echo "  workers: 15 | Issue 30TPS/30s | Verify 40->200TPS/30s"
echo "============================================="

for i in $(seq $START_RUN $END_RUN); do
    echo -e "\n\n============================================="
    echo "  Running S2 (BLAKE3) — TPS 200 — Run $i/$END_RUN"
    echo "============================================="

    # Run Caliper Benchmark
    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig "$CONFIG" \
        --caliper-flow-only-test \
        --caliper-fabric-gateway-enabled

    EXIT_CODE=$?

    # Define output directory for this run
    OUT_DIR="../results/20run_M2/tps200/run${i}"

    # Create the directory
    mkdir -p "$OUT_DIR"

    # Move and rename the report
    if [ -f report.html ]; then
        mv report.html "$OUT_DIR/caliper_raw_report.html"
        echo "✅ Run $i report saved → $OUT_DIR/caliper_raw_report.html"
    else
        echo "❌ ERROR: report.html was not generated for Run $i (caliper exit code: $EXIT_CODE)"
    fi

    # Wait for network to stabilize between runs (skip after last run)
    if [ $i -lt $END_RUN ]; then
        echo "⏳ Waiting 60s for network to stabilize before Run $((i+1))..."
        sleep 60
    fi
done

echo -e "\n============================================="
echo " 🎉 S2 BLAKE3 TPS-200 Runs $START_RUN-$END_RUN completed!"
echo "============================================="
