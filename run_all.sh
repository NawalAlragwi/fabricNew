#!/usr/bin/env bash
# =============================================================================
#  run_all.sh  —  BCMS Report Pipeline
#  Cleans HTML outputs, runs all Python generators, copies Caliper report,
#  and lists results/ with sizes.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

echo "════════════════════════════════════════════════════════"
echo "  BCMS Report Pipeline  —  $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "════════════════════════════════════════════════════════"
echo ""

# ── 1. Clean old HTML outputs ─────────────────────────────────────────────────
echo "▶  [1/5] Cleaning results/*.html …"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR"/*.html
echo "   ✓ Cleaned HTML files"
echo ""

# ── 2. Run Python report generators ──────────────────────────────────────────
echo "▶  [2/5] Running generate_hybrid_batch_report.py …"
python3 "$SCRIPT_DIR/generate_hybrid_batch_report.py"
echo ""

echo "▶  [3/5] Running generate_hybrid_only_report.py …"
python3 "$SCRIPT_DIR/generate_hybrid_only_report.py"
echo ""

echo "▶  [4/5] Running generate_four_reports.py …"
if [ -f "$SCRIPT_DIR/generate_four_reports.py" ]; then
    python3 "$SCRIPT_DIR/generate_four_reports.py" 2>/dev/null \
        && echo "   ✓ Four-scenario reports generated" \
        || echo "   ⚠ generate_four_reports.py exited non-zero (continuing)"
else
    echo "   ℹ generate_four_reports.py not found — skipping"
fi
echo ""

# ── 3. Copy Caliper workspace report if it exists ─────────────────────────────
echo "▶  [4.5] Checking for Caliper workspace report …"
CALIPER_SRC="$SCRIPT_DIR/caliper-workspace/report.html"
CALIPER_DST="$RESULTS_DIR/report_sha256_final.html"
if [ -f "$CALIPER_SRC" ]; then
    cp "$CALIPER_SRC" "$CALIPER_DST"
    echo "   ✓ Copied $CALIPER_SRC → $CALIPER_DST"
else
    echo "   ℹ Caliper workspace report not found at $CALIPER_SRC"
    if [ ! -f "$CALIPER_DST" ]; then
        echo "   ℹ No existing report_sha256_final.html — skipping"
    else
        echo "   ✓ Existing $CALIPER_DST retained"
    fi
fi
echo ""

# ── 4. Generate security / Tamarin report (if generator exists) ──────────────
if [ -f "$SCRIPT_DIR/generate_tamarin_report.py" ]; then
    echo "▶  Running generate_tamarin_report.py …"
    python3 "$SCRIPT_DIR/generate_tamarin_report.py" 2>/dev/null \
        && echo "   ✓ Tamarin report generated" \
        || echo "   ⚠ generate_tamarin_report.py exited non-zero (continuing)"
    echo ""
fi

# ── 5. List results/ with sizes ───────────────────────────────────────────────
echo "▶  [5/5] Contents of results/ :"
echo ""
if command -v du &>/dev/null; then
    (cd "$RESULTS_DIR" && ls -lh *.html 2>/dev/null \
        | awk '{printf "   %-50s %s\n", $9, $5}' \
        || echo "   (no HTML files found)")
fi
echo ""
echo "   JSON / data files:"
(cd "$RESULTS_DIR" && find . -maxdepth 2 -name "*.json" \
    | sort | xargs -I{} du -h {} 2>/dev/null \
    | awk '{printf "   %-50s %s\n", $2, $1}') || true
echo ""
echo "════════════════════════════════════════════════════════"
echo "  Pipeline complete  ✓"
echo "════════════════════════════════════════════════════════"
