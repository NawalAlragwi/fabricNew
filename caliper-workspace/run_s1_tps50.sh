#!/bin/bash
set -e

WORKSPACE_DIR="/mnt/c/Users/USERW/pro1/fabricNew/caliper-workspace"
cd "$WORKSPACE_DIR" || { echo "❌ Cannot cd to workspace"; exit 1; }

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

CALIPER_BIN="$WORKSPACE_DIR/node_modules/.bin/caliper"
export NODE_OPTIONS="--max-old-space-size=8192"

CONFIG="All_benchmarks/sha256/bcms-s-sha256-tps50.yaml"

echo "============================================="
echo "  S1 SHA-256 TPS-50"
echo "  Config    : $CONFIG"
echo "============================================="

node "$CALIPER_BIN" launch manager \
    --caliper-workspace "$WORKSPACE_DIR" \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig "$CONFIG" \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

EXIT_CODE=$?

if [ -f "$WORKSPACE_DIR/report.html" ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUT_DIR="$WORKSPACE_DIR/reports/sha256_tps50_${TIMESTAMP}"
    mkdir -p "$OUT_DIR"
    cp "$WORKSPACE_DIR/report.html" "$OUT_DIR/caliper_raw_report.html"
    cp "$WORKSPACE_DIR/report.html" "$WORKSPACE_DIR/report_S1_TPS50.html"
    echo "✅ Report saved to report_S1_TPS50.html and $OUT_DIR"
else
    echo "❌ ERROR: report.html was not generated"
fi

exit $EXIT_CODE
