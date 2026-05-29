#!/bin/bash
# ============================================================
#  S1 — SHA-256 | TPS 200 | 3 Rounds
#  Benchmark: bcms-s-sha256-tps200
#  workers: 4
#  Round 1 — IssueCertificate:    30 TPS / 60s
#  Round 2 — HashOnlyBenchmark:   10 TPS / 60s
#  Round 3 — VerifyCertificate:   40->200 TPS (linear) / 120s
# ============================================================

WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WORKSPACE_DIR" || { echo "❌ Cannot cd to workspace"; exit 1; }

# ── تفعيل nvm ────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# ── التحقق من وجود caliper ───────────────────────────────────
CALIPER_BIN="$WORKSPACE_DIR/node_modules/.bin/caliper"
if [ ! -f "$CALIPER_BIN" ]; then
    echo "❌ ERROR: caliper not found at $CALIPER_BIN"
    echo "   Run: npm install"
    exit 1
fi

export NODE_OPTIONS="--max-old-space-size=8192"

CONFIG="All_benchmarks/sha256/bcms-s-sha256-tps200.yaml"

echo ""
echo "============================================="
echo "  S1 SHA-256 TPS-200 — 3 Rounds"
echo "  Workspace : $WORKSPACE_DIR"
echo "  Config    : $CONFIG"
echo "  Caliper   : $CALIPER_BIN"
echo "  workers   : 4"
echo "  Round 1   : IssueCertificate     — 30 TPS / 60s"
echo "  Round 2   : HashOnlyBenchmark    — 10 TPS / 60s"
echo "  Round 3   : VerifyCertificate    — 40->200 TPS / 120s"
echo "============================================="
echo ""

node "$CALIPER_BIN" launch manager \
    --caliper-workspace "$WORKSPACE_DIR" \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig "$CONFIG" \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

EXIT_CODE=$?

echo ""
if [ -f "$WORKSPACE_DIR/report.html" ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUT_DIR="$WORKSPACE_DIR/reports/sha256_tps200_${TIMESTAMP}"
    mkdir -p "$OUT_DIR"
    cp "$WORKSPACE_DIR/report.html" "$OUT_DIR/caliper_raw_report.html"
    echo "✅ Report saved → $OUT_DIR/caliper_raw_report.html"
    echo "✅ Original report.html kept in workspace root"
else
    echo "❌ ERROR: report.html was not generated (caliper exit code: $EXIT_CODE)"
fi

echo ""
echo "============================================="
echo " 🎉 SHA-256 TPS-200 — 3 Rounds completed!"
echo "   Exit code: $EXIT_CODE"
echo "============================================="
