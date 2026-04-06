#!/usr/bin/env bash
# =============================================================================
#  run_s4_benchmark.sh — S4 Hybrid-Batch Benchmark Execution Script
#  Branch: mirage-batch | BCMS Ph.D. Research — §4.3 Batching Contribution
#  Version: 7.0
# =============================================================================
#
#  PURPOSE:
#    Execute ONLY Scenario S4 (Hybrid-Batch, batchSize=10) with all
#    performance-maximizing settings applied. This script is the SINGLE
#    authoritative entry point for running the S4 benchmark.
#
#  INFRASTRUCTURE PRECONDITIONS (must be met BEFORE running this script):
#    1. Fabric test-network is UP with the tuned configtx.yaml:
#         BatchTimeout=500ms  MaxMessageCount=1000
#         AbsoluteMaxBytes=99MB  PreferredMaxBytes=2MB
#    2. compose-test-net.yaml has:
#         GOMAXPROCS=0 on orderer, peer0.org1, peer0.org2
#         CORE_CHAINCODE_EXECUTETIMEOUT=300s on peer0.org1, peer0.org2
#         No cpus:/cpu_quota:/deploy.resources.limits on any container
#    3. Chaincode bcms-hybrid is deployed and committed on mychannel.
#    4. Caliper is installed: npm install && npx caliper bind --caliper-bind-sut fabric:2.5
#
#  USAGE:
#    chmod +x run_s4_benchmark.sh
#    ./run_s4_benchmark.sh
#
#  EXACT TERMINAL COMMAND (one-liner):
#    cd caliper-workspace && \
#    NODE_OPTIONS="--max-old-space-size=8192" \
#    npx caliper launch manager \
#      --caliper-workspace . \
#      --caliper-networkconfig networks/networkConfig.yaml \
#      --caliper-benchconfig benchmarks/benchConfig-S4-HybridBatch.yaml \
#      --caliper-flow-only-test \
#      --caliper-fabric-gateway-enabled
#
# =============================================================================

set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Script must run from caliper-workspace ───────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  BCMS S4 Hybrid-Batch Benchmark — Maximized Throughput v7.0${NC}"
echo -e "${BOLD}${CYAN}  Branch: mirage-batch | batchSize=10 | workers=25${NC}"
echo -e "${BOLD}${CYAN}  Linear ramp: 200 → 2000 TPS | Duration: 90s (batch round)${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Step 0: Environment validation ──────────────────────────────────────
echo -e "${YELLOW}[PRE-CHECK] Validating infrastructure...${NC}"

# Verify Caliper workspace files
REQUIRED_FILES=(
    "benchmarks/benchConfig-S4-HybridBatch.yaml"
    "workload/issueCertificateBatch.js"
    "workload/issueCertificate.js"
    "workload/verifyCertificate.js"
    "workload/queryAllCertificates.js"
    "workload/revokeCertificate.js"
    "workload/getCertificatesByStudent.js"
    "workload/getAuditLogs.js"
    "networks/networkConfig.yaml"
)
MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo -e "  ${RED}✗ MISSING: $f${NC}"
        MISSING=1
    else
        echo -e "  ${GREEN}✓ Found: $f${NC}"
    fi
done
if [ "$MISSING" -eq 1 ]; then
    echo -e "${RED}[ABORT] Missing required files. Fix above errors first.${NC}"
    exit 1
fi

# Verify Docker containers are running
echo ""
echo -e "${YELLOW}[PRE-CHECK] Verifying Fabric network containers...${NC}"
REQUIRED_CONTAINERS=("orderer.example.com" "peer0.org1.example.com" "peer0.org2.example.com")
for c in "${REQUIRED_CONTAINERS[@]}"; do
    if docker inspect "$c" > /dev/null 2>&1; then
        STATUS=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null)
        if [ "$STATUS" = "running" ]; then
            echo -e "  ${GREEN}✓ $c is running${NC}"
        else
            echo -e "  ${RED}✗ $c exists but status='$STATUS' (not running)${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ $c not found (network may not be started, continuing anyway)${NC}"
    fi
done

# Verify GOMAXPROCS=0 on critical containers (advisory only)
echo ""
echo -e "${YELLOW}[PRE-CHECK] Verifying container CPU configuration...${NC}"
for c in "orderer.example.com" "peer0.org1.example.com" "peer0.org2.example.com"; do
    if docker inspect "$c" > /dev/null 2>&1; then
        NANO_CPUS=$(docker inspect --format='{{.HostConfig.NanoCpus}}' "$c" 2>/dev/null || echo "0")
        CPU_QUOTA=$(docker inspect --format='{{.HostConfig.CpuQuota}}' "$c" 2>/dev/null || echo "0")
        if [ "$NANO_CPUS" = "0" ] && [ "$CPU_QUOTA" = "0" ]; then
            echo -e "  ${GREEN}✓ $c: no CPU limits (NanoCpus=0, CpuQuota=0)${NC}"
        else
            echo -e "  ${YELLOW}⚠ $c: NanoCpus=$NANO_CPUS CpuQuota=$CPU_QUOTA (may limit S4 throughput)${NC}"
        fi
    fi
done

# ── Step 1: Delete old report to prevent stale data ─────────────────────
echo ""
echo -e "${YELLOW}[STEP 1] Removing stale report files...${NC}"
rm -f report.html report_custom.html report_S4_HybridBatch.html
echo -e "  ${GREEN}✓ Cleaned previous reports${NC}"

# ── Step 2: Set NODE_OPTIONS — CRITICAL for 2000 TPS ────────────────────
echo ""
echo -e "${YELLOW}[STEP 2] Configuring Node.js heap memory...${NC}"
export NODE_OPTIONS="--max-old-space-size=8192"
echo -e "  ${GREEN}✓ NODE_OPTIONS=$NODE_OPTIONS${NC}"
echo -e "  ${CYAN}  Rationale: At 2000 TPS × 25 workers, Caliper holds ~1,800 in-flight${NC}"
echo -e "  ${CYAN}  TX objects in memory simultaneously. Default 512MB heap will OOM.${NC}"
echo -e "  ${CYAN}  8192MB (8 GB) provides a 16× safety margin.${NC}"

# ── Step 3: Print benchmark parameters ──────────────────────────────────
echo ""
echo -e "${BOLD}[STEP 3] S4 Benchmark Parameters:${NC}"
echo -e "  Config file:      benchmarks/benchConfig-S4-HybridBatch.yaml"
echo -e "  Workers:          ${BOLD}25${NC} (Little's Law: 2000 TPS × 0.9s latency)"
echo -e "  Batch round TPS:  ${BOLD}linear 200 → 2000${NC} (90s duration)"
echo -e "  batchSize:        ${BOLD}10 certs per TX${NC} (STRICTLY enforced in YAML)"
echo -e "  Other rounds:     ${BOLD}fixed-rate 1000 TPS${NC} (30s each)"
echo -e "  Effective target: ${BOLD}~2,000 certs/s${NC} (200 TPS × 10)"
echo -e ""
echo -e "  configtx.yaml:"
echo -e "    BatchTimeout:     ${BOLD}500ms${NC}"
echo -e "    MaxMessageCount:  ${BOLD}1000${NC}"
echo -e "    AbsoluteMaxBytes: ${BOLD}99 MB${NC}"
echo -e "    PreferredMaxBytes:${BOLD}2 MB${NC}"
echo -e ""
echo -e "  Docker:"
echo -e "    GOMAXPROCS=0 (orderer, peer0.org1, peer0.org2)"
echo -e "    CORE_CHAINCODE_EXECUTETIMEOUT=300s (peer0.org1, peer0.org2)"
echo -e "    No cpus:/cpu_quota:/deploy.resources.limits on any container"

# ── Step 4: Run Caliper benchmark ───────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Launching Caliper S4 Benchmark...${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Exact command:${NC}"
echo -e "  NODE_OPTIONS=\"--max-old-space-size=8192\" \\"
echo -e "  npx caliper launch manager \\"
echo -e "    --caliper-workspace . \\"
echo -e "    --caliper-networkconfig networks/networkConfig.yaml \\"
echo -e "    --caliper-benchconfig benchmarks/benchConfig-S4-HybridBatch.yaml \\"
echo -e "    --caliper-flow-only-test \\"
echo -e "    --caliper-fabric-gateway-enabled"
echo ""

START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo -e "  Started: $START_TIME"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# THE ACTUAL EXECUTION COMMAND
# NODE_OPTIONS is already exported above.
# All flags explained:
#   --caliper-workspace .              → caliper-workspace/ is the root
#   --caliper-networkconfig            → Fabric network config (TLS certs, endpoints)
#   --caliper-benchconfig              → S4-specific benchmark YAML
#   --caliper-flow-only-test           → skip install/init (chaincode already deployed)
#   --caliper-fabric-gateway-enabled   → use Fabric Gateway API (required for Fabric 2.5)
# ─────────────────────────────────────────────────────────────────────────────
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig-S4-HybridBatch.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled

BENCH_EXIT=$?
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ── Step 5: Post-benchmark verification ─────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "  Benchmark finished: $END_TIME"
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ $BENCH_EXIT -ne 0 ]; then
    echo -e "${RED}[ERROR] Caliper exited with code $BENCH_EXIT.${NC}"
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo -e "  1. Fabric containers running? → docker ps | grep hyperledger"
    echo -e "  2. Chaincode deployed?        → peer chaincode list --installed"
    echo -e "  3. networkConfig.yaml paths?  → check TLS cert paths"
    echo -e "  4. Caliper bound?             → npx caliper bind --caliper-bind-sut fabric:2.5"
    exit $BENCH_EXIT
fi

# ── Step 6: Generate custom S4 HTML report ──────────────────────────────
if [ -f "report.html" ]; then
    REPORT_SIZE=$(stat -c%s "report.html" 2>/dev/null || stat -f%z "report.html" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Default Caliper report: report.html ($REPORT_SIZE bytes)${NC}"

    echo ""
    echo -e "${YELLOW}[STEP 6] Generating S4 custom HTML report...${NC}"

    # Main custom report (all rounds)
    if [ -f "generate_custom_report.js" ]; then
        node generate_custom_report.js report.html report_custom.html
        CUSTOM_SIZE=$(stat -c%s "report_custom.html" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ Custom report: report_custom.html ($CUSTOM_SIZE bytes)${NC}"
    fi

    # Per-scenario S4 report
    if [ -f "generate_scenario_reports.js" ]; then
        node generate_scenario_reports.js
        echo -e "${GREEN}✓ Scenario reports: report_S{1,2,3,4}*.html${NC}"
    fi

    echo ""
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  S4 BENCHMARK COMPLETE — ALL REPORTS GENERATED${NC}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Started:    $START_TIME"
    echo -e "  Finished:   $END_TIME"
    echo -e "  Reports:"
    echo -e "    $(pwd)/report.html            (Caliper default)"
    echo -e "    $(pwd)/report_custom.html     (PhD custom report)"
    echo -e "    $(pwd)/report_S4_HybridBatch.html (S4 scenario dashboard)"
    echo ""
    echo -e "  ${CYAN}Expected results (v7.0 tuning):${NC}"
    echo -e "    IssueCertificateBatch:  ~180-220 Caliper TPS"
    echo -e "    Effective certs/s:      ~1,800-2,200  (TPS × 10)"
    echo -e "    vs S1 SHA-256 baseline: ~13-16× improvement"
    echo -e "    Failure rate:           0.00%"
    echo -e "    Avg TX latency:         ~0.7-1.1 s"
    echo ""
else
    echo -e "${RED}[ERROR] report.html was NOT generated!${NC}"
    echo -e "${YELLOW}Check caliper.log or caliper output above for errors.${NC}"
    echo -e "Common causes:"
    echo -e "  - Network containers not running"
    echo -e "  - Chaincode not committed on mychannel"
    echo -e "  - TLS cert path mismatch in networkConfig.yaml"
    echo -e "  - Caliper bind version: run 'npx caliper bind --caliper-bind-sut fabric:2.5'"
    exit 1
fi
