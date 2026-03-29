#!/usr/bin/env bash
# ============================================================================
#  BCMS — Unified Execution Pipeline
#  Hybrid Blockchain Framework (SHA-256 + BLAKE3) with Batching
#
#  Usage:  bash run_all.sh [--tps=100] [--batch=10]
#
#  Steps:
#    1. Clean previous HTML reports
#    2. Run REAL cryptographic benchmarks (SHA-256, BLAKE3, Hybrid, Batch)
#    3. Generate 4 professional HTML reports + combined dashboard
#    4. Copy Caliper workspace report if available
#    5. List all result files with sizes
# ============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$ROOT_DIR/results"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
TPS_TARGET=100
BATCH_SIZE=10

# Parse args
for arg in "$@"; do
    case $arg in
        --tps=*)   TPS_TARGET="${arg#*=}" ;;
        --batch=*) BATCH_SIZE="${arg#*=}" ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   BCMS — Hybrid Blockchain Framework                    ║"
echo "║   SHA-256 + BLAKE3 Double-Lock Pipeline + Batching      ║"
echo "║   Real Benchmarks · 4 Professional Reports              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Root:       $ROOT_DIR"
echo "  Results:    $RESULTS_DIR"
echo "  TPS Target: $TPS_TARGET"
echo "  Batch Size: $BATCH_SIZE"
echo "  Start Time: $NOW"
echo ""

# ── Step 1: Clean previous HTML reports ──────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "  STEP 1: Clean previous HTML reports"
echo "══════════════════════════════════════════════"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR"/*.html
rm -f "$RESULTS_DIR"/final_comparison/*.html 2>/dev/null || true
echo "  ✓ Cleaned: $RESULTS_DIR/*.html"

# ── Step 2: Install dependencies ─────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  STEP 2: Check Python dependencies"
echo "══════════════════════════════════════════════"
python3 -c "import blake3; print('  ✓ blake3 available')" 2>/dev/null || {
    echo "  Installing blake3..."
    pip install blake3 -q
}
echo "  ✓ All dependencies ready"

# ── Step 3: Run REAL benchmarks ──────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  STEP 3: Run REAL Cryptographic Benchmarks"
echo "          (100,000 iterations per algorithm)"
echo "══════════════════════════════════════════════"
cd "$ROOT_DIR"
python3 run_real_benchmark.py
echo "  ✓ Real benchmarks complete"

# ── Step 4: Generate 4 HTML reports ──────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  STEP 4: Generate 4 Professional HTML Reports"
echo "══════════════════════════════════════════════"
python3 generate_four_reports.py
echo "  ✓ All reports generated"

# ── Step 5: Sync Caliper workspace report if available ───────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  STEP 5: Sync Caliper workspace report"
echo "══════════════════════════════════════════════"
CALIPER_REPORT="$ROOT_DIR/caliper-workspace/report.html"
if [ -f "$CALIPER_REPORT" ]; then
    cp "$CALIPER_REPORT" "$RESULTS_DIR/report_sha256_final.html"
    echo "  ✓ Copied caliper-workspace/report.html → results/report_sha256_final.html"
else
    echo "  ⚠ No caliper-workspace/report.html found (Fabric network not running)"
    echo "  → Using existing report_sha256_final.html"
fi

# ── Step 6: Final report listing ─────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  STEP 6: Final Report Listing"
echo "══════════════════════════════════════════════"
echo ""
echo "  results/ directory:"
echo "  ─────────────────────────────────────────────"
printf "  %-45s %s\n" "FILE" "SIZE"
echo "  ─────────────────────────────────────────────"
for f in "$RESULTS_DIR"/*.html; do
    [ -f "$f" ] || continue
    size=$(du -sh "$f" | cut -f1)
    fname=$(basename "$f")
    printf "  %-45s %s\n" "$fname" "$size"
done
echo "  ─────────────────────────────────────────────"
echo ""

# ── Step 7: Print benchmark summary ──────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "  BENCHMARK SUMMARY (Real Measurements)"
echo "══════════════════════════════════════════════"
python3 - <<'PYEOF'
import json, os
f = open("results/hash_benchmark.json")
d = json.load(f)
h = d["hash_benchmarks"]
m = d["fabric_metrics"]
print(f"  SHA-256    : {h['sha256']['throughput_hps']:>12,.0f} h/s | {h['sha256']['mean_us']} µs mean")
print(f"  BLAKE3     : {h['blake3']['throughput_hps']:>12,.0f} h/s | {h['blake3']['mean_us']} µs mean")
print(f"  Hybrid     : {h['hybrid']['throughput_hps']:>12,.0f} h/s | {h['hybrid']['mean_us']} µs mean")
print(f"  Hybrid/cert: {h['hybrid_batch_per_cert']['throughput_hps']:>12,.0f} h/s | {h['hybrid_batch_per_cert']['mean_us']} µs/cert")
print()
print(f"  S1 SHA-256:       {m['S1_sha256']['tps']:.2f} TPS | {m['S1_sha256']['latency_ms']} ms")
print(f"  S2 BLAKE3:        {m['S2_blake3']['tps']:.2f} TPS | {m['S2_blake3']['latency_ms']} ms")
print(f"  S3 Hybrid:        {m['S3_hybrid']['tps']:.2f} TPS | {m['S3_hybrid']['latency_ms']} ms")
print(f"  S4 Hybrid+Batch: {m['S4_hybrid_batch']['tps']:.2f} TPS | Eff: {m['S4_hybrid_batch']['effective_cert_tps']:.1f} | {m['S4_hybrid_batch']['latency_ms']} ms")
PYEOF

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   ✅ PIPELINE COMPLETE — All reports in results/         ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║   📊 S1 SHA-256:    results/report_scenario1_sha256.html ║"
echo "║   📊 S2 BLAKE3:     results/report_scenario2_blake3.html ║"
echo "║   📊 S3 Hybrid:     results/report_scenario3_hybrid.html ║"
echo "║   📊 S4 Batch:      results/report_scenario4_batch.html  ║"
echo "║   📊 Dashboard:     results/four_scenario_report.html    ║"
echo "║                                                          ║"
echo "║   ⚠  All hash data: REAL measurements on this machine    ║"
echo "║   ⚠  Fabric TPS:    real hash + validated network model  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  End Time: $(date '+%Y-%m-%d %H:%M:%S')"
