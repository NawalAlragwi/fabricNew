#!/usr/bin/env bash
# ============================================================================
#  fix_conflicts.sh — Resolve Caliper dependency conflicts
#
#  Problem: "Multiple bindings for fabric" error occurs when both
#  @hyperledger/fabric-gateway AND @hyperledger/caliper-fabric are installed,
#  as they register duplicate gRPC service handlers.
#
#  Solution: Remove @hyperledger/fabric-gateway from node_modules before
#  running Caliper benchmarks. Caliper 0.6.0 includes its own fabric binding.
# ============================================================================
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_MODULES="${WORKSPACE_DIR}/node_modules"

echo "==> Resolving Caliper fabric binding conflicts..."

# Remove fabric-gateway to prevent duplicate binding error
if [ -d "${NODE_MODULES}/@hyperledger/fabric-gateway" ]; then
    echo "  Removing @hyperledger/fabric-gateway (conflicts with caliper-fabric)..."
    rm -rf "${NODE_MODULES}/@hyperledger/fabric-gateway"
    echo "  Done."
else
    echo "  @hyperledger/fabric-gateway not found (already clean)."
fi

# Also remove fabric-network if it conflicts (Caliper 0.6 is incompatible with >2.x)
if [ -d "${NODE_MODULES}/fabric-network" ]; then
    local_ver=$(node -e "try{console.log(require('./node_modules/fabric-network/package.json').version)}catch(e){console.log('unknown')}" 2>/dev/null || echo "unknown")
    echo "  fabric-network version: ${local_ver}"
    # Only remove if it's > 2.x (incompatible with Caliper 0.6)
    major=$(echo "$local_ver" | cut -d'.' -f1)
    if [ "$major" -gt 2 ] 2>/dev/null; then
        echo "  fabric-network v${local_ver} may conflict — leaving in place (Caliper handles internally)"
    fi
fi

echo "==> Conflict resolution complete."
echo ""
echo "Now run Caliper with:"
echo "  npx caliper launch manager --caliper-workspace . \\"
echo "      --caliper-networkconfig networks/networkConfig.yaml \\"
echo "      --caliper-benchconfig benchmarks/benchConfig.yaml \\"
echo "      --caliper-flow-only-test"
