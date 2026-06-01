#!/bin/bash
# ============================================================================
#  run_table9_concurrent.sh
#  Runs Table 9: Concurrent User Load Tests for all 4 models (M1–M4)
#
#  Results map to Table 9 in the research paper:
#    M1 = SHA-256     | M2 = BLAKE3   | M3 = Hybrid   | M4 = Hybrid-Batch
#
#  Usage (from caliper-workspace directory):
#    bash run_table9_concurrent.sh
#
#  Prerequisites:
#    - Fabric test-network is UP and running
#    - All 4 chaincodes deployed:
#        bcms-sha256 / bcms-blake3 / bcms-hybrid / bcms-hybrid-batch
#    - networkConfig.yaml points to correct peer/orderer endpoints
#    - node_modules installed (npm install already done)
# ============================================================================

set -e

WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
NETWORKS_DIR="$WORKSPACE_DIR/networks/networkConfig.yaml"
REPORTS_DIR="$WORKSPACE_DIR/reports/table9"
BENCHMARKS_DIR="$WORKSPACE_DIR/benchmarks"

mkdir -p "$REPORTS_DIR"

echo "========================================================"
echo "  TABLE 9 — Concurrent User Load Benchmark"
echo "  Starting: $(date)"
echo "========================================================"

# Helper function to run a single Caliper benchmark
run_caliper() {
    local MODEL_NAME=$1
    local BENCH_YAML=$2
    local REPORT_NAME=$3

    echo ""
    echo "──────────────────────────────────────────────────────"
    echo "  Running: $MODEL_NAME"
    echo "  Config:  $BENCH_YAML"
    echo "  Started: $(date)"
    echo "──────────────────────────────────────────────────────"

    npx caliper launch manager \
        --caliper-workspace "$WORKSPACE_DIR" \
        --caliper-networkconfig "$NETWORKS_DIR" \
        --caliper-benchconfig "$BENCHMARKS_DIR/$BENCH_YAML" \
        --caliper-flow-only-test \
        --caliper-fabric-timeout-invokeorquery 180000 \
        --caliper-report-path "$REPORTS_DIR/$REPORT_NAME.html" \
        2>&1 | tee "$REPORTS_DIR/${REPORT_NAME}.log"

    echo "  ✅ Finished: $MODEL_NAME → $REPORTS_DIR/$REPORT_NAME.html"
}

# ─────────────────────────────────────────────────────────────────────────────
# M1 — SHA-256 Concurrent Load Test
# Expected: 10u→6.89s | 50u→9.41s | 100u→12.87s avg | 18.24s max
# ─────────────────────────────────────────────────────────────────────────────
run_caliper \
    "M1 — SHA-256 (10 / 50 / 100 Users)" \
    "table9-S1-SHA256-concurrent.yaml" \
    "table9_M1_SHA256"

# ─────────────────────────────────────────────────────────────────────────────
# M2 — BLAKE3 Concurrent Load Test
# Expected: 10u→2.14s | 50u→3.18s | 100u→4.92s avg | 7.13s max
# ─────────────────────────────────────────────────────────────────────────────
run_caliper \
    "M2 — BLAKE3 (10 / 50 / 100 Users)" \
    "table9-S2-BLAKE3-concurrent.yaml" \
    "table9_M2_BLAKE3"

# ─────────────────────────────────────────────────────────────────────────────
# M3 — Hybrid SHA-256+BLAKE3 Concurrent Load Test
# Expected: 10u→8.92s | 50u→11.34s | 100u→15.61s avg | 21.43s max
# ─────────────────────────────────────────────────────────────────────────────
run_caliper \
    "M3 — Hybrid (10 / 50 / 100 Users)" \
    "table9-S3-Hybrid-concurrent.yaml" \
    "table9_M3_Hybrid"

# ─────────────────────────────────────────────────────────────────────────────
# M4 — Hybrid-Batch Concurrent Load Test
# Expected: 10u→0.11s | 50u→0.14s | 100u→0.19s avg | 0.27s max
# ─────────────────────────────────────────────────────────────────────────────
run_caliper \
    "M4 — Hybrid-Batch (10 / 50 / 100 Users)" \
    "table9-S4-HybridBatch-concurrent.yaml" \
    "table9_M4_HybridBatch"

echo ""
echo "========================================================"
echo "  TABLE 9 — All Tests COMPLETE"
echo "  Finished: $(date)"
echo ""
echo "  Reports saved to: $REPORTS_DIR/"
echo ""
echo "  Files:"
echo "    table9_M1_SHA256.html      ← M1 results"
echo "    table9_M2_BLAKE3.html      ← M2 results"
echo "    table9_M3_Hybrid.html      ← M3 results"
echo "    table9_M4_HybridBatch.html ← M4 results"
echo ""
echo "  How to read results (Caliper HTML report):"
echo "    Round label = user tier (e.g. SHA256-100-Users)"
echo "    'Avg Latency (s)' column = Table 9 Avg value"
echo "    'Max Latency (s)' column = Table 9 Max value (100-user round)"
echo "========================================================"
