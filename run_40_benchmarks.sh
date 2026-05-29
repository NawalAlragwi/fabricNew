#!/bin/bash
# ============================================================================
#  BCMS — 40-Run Benchmark Automation Script
#  Models: M1 (SHA-256) | M2 (BLAKE3) | M3 (Hybrid) | M4 (Hybrid-Batch)
#  Runs each model 10 times with full Docker teardown between runs
# ============================================================================

set -uo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURABLE VARIABLES — adjust these to match your environment
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALIPER_WORKSPACE="${SCRIPT_DIR}/caliper-workspace"
NETWORK_DIR="${SCRIPT_DIR}/test-network"
RESULTS_DIR="${SCRIPT_DIR}/results/40runs"
DOCKER_COMPOSE_FILE="${NETWORK_DIR}/compose/compose-test-net.yaml"

RUNS_PER_MODEL=10
COOLDOWN_BETWEEN_RUNS=30      # seconds between runs
NETWORK_STARTUP_WAIT=60       # seconds after docker-compose up
CONTAINER_HEALTH_RETRIES=12   # × 5s = 60s max wait for containers

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
MASTER_LOG="${RESULTS_DIR}/master_${TIMESTAMP}.log"
CSV_FILE="${RESULTS_DIR}/all_runs_raw.csv"

# Model → bench config file mapping
declare -A MODEL_BENCHCONFIG=(
    [M1]="benchmarks/benchConfig_s1_sha256_tps200.yaml"
    [M2]="benchmarks/benchConfig_s2_blake3_tps200.yaml"
    [M3]="benchmarks/benchConfig_s3_hybrid.yaml"
    [M4]="benchmarks/benchConfig_s4_hybrid_batch.yaml"
)
# Model → chaincode name mapping
declare -A MODEL_CCNAME=(
    [M1]="bcms-sha256"
    [M2]="bcms-blake3"
    [M3]="bcms-hybrid"
    [M4]="bcms-hybrid-batch"
)
# Model → chaincode path mapping
declare -A MODEL_CCPATH=(
    [M1]="chaincode-bcms/sha256"
    [M2]="chaincode-bcms/blake3"
    [M3]="chaincode-bcms/hybrid"
    [M4]="chaincode-bcms/hybrid-batch"
)

# ─────────────────────────────────────────────────────────────────────────────
# COLORS & LOGGING
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}" | tee -a "$MASTER_LOG"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN: $*${NC}" | tee -a "$MASTER_LOG"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $*${NC}" | tee -a "$MASTER_LOG"; }
info()  { echo -e "${CYAN}[$(date '+%H:%M:%S')] $*${NC}" | tee -a "$MASTER_LOG"; }
step()  {
    echo "" | tee -a "$MASTER_LOG"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}" | tee -a "$MASTER_LOG"
    echo -e "${BOLD}${BLUE}  $*${NC}" | tee -a "$MASTER_LOG"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}" | tee -a "$MASTER_LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# PROGRESS INDICATOR
# ─────────────────────────────────────────────────────────────────────────────
show_progress() {
    local model="$1" run="$2" total="$3" status="$4"
    local bar="" filled=$(( run * 20 / total )) i
    for (( i=0; i<20; i++ )); do
        [ $i -lt $filled ] && bar+="█" || bar+="░"
    done
    echo -e "${BOLD}${CYAN}  ▶ [${model} | Run ${run}/${total}] [${bar}] ${status}${NC}" | tee -a "$MASTER_LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER NETWORK MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────
teardown_network() {
    info "  Tearing down network (docker-compose down -v)..."
    cd "$NETWORK_DIR"
    # Stop chaincode containers first
    docker ps --format '{{.Names}}' 2>/dev/null | grep "^dev-peer" | \
        xargs -r docker stop 2>/dev/null || true
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep "^dev-peer" | \
        xargs -r docker rm -f 2>/dev/null || true
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^dev-peer" | \
        xargs -r docker rmi -f 2>/dev/null || true
    # Full network teardown
    ./network.sh down 2>&1 | tee -a "$MASTER_LOG" || true
    docker volume prune -f 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    cd "$SCRIPT_DIR"
    log "  ✓ Network torn down"
}

startup_network() {
    local cc_name="$1" cc_path="$2"
    info "  Starting network (chaincode: ${cc_name})..."
    cd "$NETWORK_DIR"
    ./network.sh up createChannel -c mychannel -ca -s couchdb 2>&1 | tee -a "$MASTER_LOG" || {
        error "  Network startup failed"; cd "$SCRIPT_DIR"; return 1
    }
    # Deploy chaincode
    export GOFLAGS="-mod=vendor"; export GOWORK="off"; export GOPROXY="off"
    ./network.sh deployCC \
        -ccn "${cc_name}" -ccp "${SCRIPT_DIR}/${cc_path}" \
        -ccl go -c mychannel \
        -ccep "OR('Org1MSP.peer','Org2MSP.peer')" \
        2>&1 | tee -a "$MASTER_LOG" || {
        error "  Chaincode deployment failed"; cd "$SCRIPT_DIR"; return 1
    }
    cd "$SCRIPT_DIR"
    log "  ✓ Network started, chaincode deployed"
}

wait_for_containers() {
    info "  Waiting ${NETWORK_STARTUP_WAIT}s for network stabilization..."
    sleep "$NETWORK_STARTUP_WAIT"
    local attempt=1
    while [ $attempt -le $CONTAINER_HEALTH_RETRIES ]; do
        local running
        running=$(docker ps --format '{{.Names}}' 2>/dev/null)
        if echo "$running" | grep -q "orderer" && \
           echo "$running" | grep -q "peer0.org1" && \
           echo "$running" | grep -q "peer0.org2" && \
           echo "$running" | grep -q "couchdb"; then
            log "  ✓ All containers healthy (attempt ${attempt})"
            return 0
        fi
        warn "  Containers not ready yet (attempt ${attempt}/${CONTAINER_HEALTH_RETRIES})..."
        sleep 5
        attempt=$(( attempt + 1 ))
    done
    error "  Containers did not become healthy in time"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# CALIPER NETWORK CONFIG GENERATION
# ─────────────────────────────────────────────────────────────────────────────
generate_network_config() {
    local cc_name="$1"
    local PEER1_TLS PEER2_TLS ORDERER_TLS
    PEER1_TLS=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com" \
        -name "ca.crt" | grep "peer0.org1" | head -1)
    PEER2_TLS=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org2.example.com" \
        -name "ca.crt" | grep "peer0.org2" | head -1)
    ORDERER_TLS=$(find "${NETWORK_DIR}/organizations/ordererOrganizations" \
        -name "*.pem" | grep "tlsca" | head -1)
    local ORG1_KEY ORG1_CERT ORG2_KEY ORG2_CERT
    ORG1_KEY=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore" \
        \( -name "*_sk" -o -name "*.pem" \) 2>/dev/null | head -1)
    ORG1_CERT=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts" \
        -name "*.pem" 2>/dev/null | head -1)
    ORG2_KEY=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore" \
        \( -name "*_sk" -o -name "*.pem" \) 2>/dev/null | head -1)
    ORG2_CERT=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts" \
        -name "*.pem" 2>/dev/null | head -1)

    mkdir -p "${CALIPER_WORKSPACE}/networks"
    # Connection profile for Org1
    cat > "${CALIPER_WORKSPACE}/networks/connection-org1.yaml" << CONNEOF
name: test-network-org1
version: "1.0.0"
client:
  organization: Org1
  connection:
    timeout:
      peer: { endorser: '300', eventHub: '300', eventReg: '300' }
      orderer: '300'
channels:
  mychannel:
    orderers: [orderer.example.com]
    peers:
      peer0.org1.example.com: { endorsingPeer: true, chaincodeQuery: true, ledgerQuery: true, eventSource: true }
      peer0.org2.example.com: { endorsingPeer: true, chaincodeQuery: false, ledgerQuery: false, eventSource: false }
organizations:
  Org1:
    mspid: Org1MSP
    peers: [peer0.org1.example.com]
orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
    tlsCACerts:
      path: '${ORDERER_TLS}'
peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      grpc.keepalive_time_ms: 120000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts:
      path: '${PEER1_TLS}'
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      grpc.keepalive_time_ms: 120000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts:
      path: '${PEER2_TLS}'
CONNEOF

    # Caliper networkConfig
    cat > "${CALIPER_WORKSPACE}/networks/networkConfig.yaml" << NETEOF
name: bcms-test-network
version: "2.0.0"
caliper:
  blockchain: fabric
channels:
  - channelName: mychannel
    contracts:
      - id: ${cc_name}
organizations:
  - mspid: Org1MSP
    identities:
      certificates:
        - name: 'User1@org1.example.com'
          clientPrivateKey:
            path: '${ORG1_KEY}'
          clientSignedCert:
            path: '${ORG1_CERT}'
    connectionProfile:
      path: 'networks/connection-org1.yaml'
      discover: false
  - mspid: Org2MSP
    identities:
      certificates:
        - name: 'User1@org2.example.com'
          clientPrivateKey:
            path: '${ORG2_KEY}'
          clientSignedCert:
            path: '${ORG2_CERT}'
    connectionProfile:
      path: 'networks/connection-org2.yaml'
      discover: false
NETEOF
    log "  ✓ Network config generated for: ${cc_name}"
}

# ─────────────────────────────────────────────────────────────────────────────
# METRIC EXTRACTION (from Caliper HTML report)
# ─────────────────────────────────────────────────────────────────────────────
extract_metrics() {
    local report_html="$1"
    local json_out="$2"

    # Use Python to parse the embedded JSON from Caliper's HTML report
    python3 - "$report_html" "$json_out" << 'PYEOF'
import sys, json, re

html_file = sys.argv[1]
json_file = sys.argv[2]

try:
    with open(html_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Extract the JSON data block Caliper embeds in its HTML report
    patterns = [
        r'benchmarkInfo["\s]*:["\s]*([^<]+)',
        r'var\s+resultsData\s*=\s*(\{.*?\});',
        r'<pre[^>]*>(.*?)</pre>',
    ]

    metrics = {
        "avg_tps": None, "avg_latency": None,
        "max_latency": None, "min_latency": None,
        "success_rate": None
    }

    # Try to find TPS from table data in the HTML
    tps_match = re.search(r'<td[^>]*>\s*([\d.]+)\s*</td>', content)

    # Search for key metric patterns
    avg_tps_m    = re.search(r'(\d+\.?\d*)\s*(?:TPS|tps)', content)
    avg_lat_m    = re.search(r'Avg\s+Latency.*?(\d+\.?\d*)\s*s', content, re.I)
    max_lat_m    = re.search(r'Max\s+Latency.*?(\d+\.?\d*)\s*s', content, re.I)
    min_lat_m    = re.search(r'Min\s+Latency.*?(\d+\.?\d*)\s*s', content, re.I)
    success_m    = re.search(r'(\d+\.?\d*)\s*%', content)

    if avg_tps_m:    metrics["avg_tps"]       = float(avg_tps_m.group(1))
    if avg_lat_m:    metrics["avg_latency"]   = float(avg_lat_m.group(1))
    if max_lat_m:    metrics["max_latency"]   = float(max_lat_m.group(1))
    if min_lat_m:    metrics["min_latency"]   = float(min_lat_m.group(1))
    if success_m:    metrics["success_rate"]  = float(success_m.group(1))

    with open(json_file, 'w') as f:
        json.dump(metrics, f, indent=2)

    print(f"Metrics extracted: {metrics}")
    sys.exit(0)

except Exception as e:
    print(f"Extraction error: {e}", file=sys.stderr)
    # Write zeros so CSV is still valid
    with open(json_file, 'w') as f:
        json.dump({"avg_tps": 0, "avg_latency": 0,
                   "max_latency": 0, "min_latency": 0,
                   "success_rate": 0, "parse_error": str(e)}, f)
    sys.exit(1)
PYEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SINGLE CALIPER RUN
# ─────────────────────────────────────────────────────────────────────────────
run_caliper() {
    local model="$1" run_num="$2" bench_cfg="$3" result_dir="$4"
    local run_log="${result_dir}/${model}_run${run_num}.txt"
    local run_json="${result_dir}/${model}_run${run_num}.json"
    local report_html="${CALIPER_WORKSPACE}/report.html"

    info "    Starting Caliper: ${bench_cfg}"
    rm -f "${report_html}" "${CALIPER_WORKSPACE}/caliper.log" 2>/dev/null || true

    cd "$CALIPER_WORKSPACE"

    NO_PROXY="localhost,127.0.0.1" no_proxy="localhost,127.0.0.1" \
    http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" \
    CALIPER_FABRIC_TIMEOUT_INVOKEORQUERY=120000 \
    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig "${bench_cfg}" \
        --caliper-flow-only-test \
        2>&1 | tee "$run_log"

    local exit_code=${PIPESTATUS[0]}
    cd "$SCRIPT_DIR"

    if [ -f "$report_html" ]; then
        cp "$report_html" "${result_dir}/${model}_run${run_num}_report.html"
        extract_metrics "${result_dir}/${model}_run${run_num}_report.html" "$run_json"
        log "    ✓ Run ${run_num} complete — report saved"
        return 0
    else
        warn "    ✗ No report.html found (exit: ${exit_code})"
        echo '{"avg_tps":0,"avg_latency":0,"max_latency":0,"min_latency":0,"success_rate":0,"error":"no_report"}' > "$run_json"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# INITIALIZE LEDGER
# ─────────────────────────────────────────────────────────────────────────────
init_ledger() {
    local cc_name="$1"
    export PATH="${SCRIPT_DIR}/bin:$PATH"
    export FABRIC_CFG_PATH="${SCRIPT_DIR}/config/"
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE="${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
    export CORE_PEER_ADDRESS=localhost:7051

    info "  Initializing ledger for ${cc_name}..."
    # Warm up to trigger image build
    local attempt=1
    while [ $attempt -le 10 ]; do
        peer chaincode query -C mychannel -n "${cc_name}" \
            -c '{"Args":["QueryAllCertificates","5",""]}' 2>/dev/null && {
            log "  ✓ Chaincode ${cc_name} ready (attempt ${attempt})"; break
        }
        sleep 8; attempt=$(( attempt + 1 ))
    done

    peer chaincode invoke \
        -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
        --tls --cafile "${NETWORK_DIR}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem" \
        -C mychannel -n "${cc_name}" \
        --peerAddresses localhost:7051 \
        --tlsRootCertFiles "${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" \
        --peerAddresses localhost:9051 \
        --tlsRootCertFiles "${NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt" \
        -c '{"function":"InitLedger","Args":[]}' 2>&1 | tee -a "$MASTER_LOG" || \
        warn "  InitLedger warning (non-fatal)"
}

# ─────────────────────────────────────────────────────────────────────────────
# CSV AGGREGATION
# ─────────────────────────────────────────────────────────────────────────────
aggregate_csv() {
    log "Aggregating results into CSV: ${CSV_FILE}"
    echo "Model,Run,AvgTPS,AvgLatency,MaxLatency,MinLatency,SuccessRate" > "$CSV_FILE"

    for model in M1 M2 M3 M4; do
        for (( run=1; run<=RUNS_PER_MODEL; run++ )); do
            local json_file="${RESULTS_DIR}/${model}/${model}_run${run}.json"
            if [ -f "$json_file" ]; then
                python3 - "$json_file" "$model" "$run" >> "$CSV_FILE" << 'PYEOF'
import sys, json
f, model, run = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(open(f))
    print(f"{model},{run},{d.get('avg_tps',0)},{d.get('avg_latency',0)},{d.get('max_latency',0)},{d.get('min_latency',0)},{d.get('success_rate',0)}")
except Exception as e:
    print(f"{model},{run},0,0,0,0,0")
PYEOF
            else
                echo "${model},${run},0,0,0,0,0" >> "$CSV_FILE"
            fi
        done
    done
    log "✓ CSV saved: ${CSV_FILE}"
    echo ""
    column -t -s',' "$CSV_FILE" | head -20
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION LOOP
# ─────────────────────────────────────────────────────────────────────────────
main() {
    mkdir -p "$RESULTS_DIR"

    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   BCMS — 40-Run Full Benchmark Automation                  ║"
    echo "║   Models: M1 M2 M3 M4  |  10 runs each  |  Full teardown  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  Start Time  : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Results Dir : ${RESULTS_DIR}"
    echo "  Log File    : ${MASTER_LOG}"
    echo ""

    # Ensure Caliper is installed
    if [ ! -f "${CALIPER_WORKSPACE}/node_modules/.bin/caliper" ]; then
        step "Installing Caliper dependencies"
        cd "$CALIPER_WORKSPACE"
        npm install 2>&1 | tee -a "$MASTER_LOG"
        npx caliper bind --caliper-bind-sut fabric:2.5 2>&1 | tee -a "$MASTER_LOG"
        cd "$SCRIPT_DIR"
    fi

    local total_runs=$(( 4 * RUNS_PER_MODEL ))
    local completed=0 failed=0

    for model in M1 M2 M3 M4; do
        local bench_cfg="${MODEL_BENCHCONFIG[$model]}"
        local cc_name="${MODEL_CCNAME[$model]}"
        local cc_path="${MODEL_CCPATH[$model]}"
        local model_dir="${RESULTS_DIR}/${model}"
        mkdir -p "$model_dir"

        step "MODEL ${model} — Chaincode: ${cc_name}"

        for (( run=1; run<=RUNS_PER_MODEL; run++ )); do
            local run_start
            run_start=$(date '+%Y-%m-%d %H:%M:%S')
            show_progress "$model" "$run" "$RUNS_PER_MODEL" "Starting..."

            # ── Teardown previous network ──────────────────────────────────
            log "  [${model} Run ${run}/${RUNS_PER_MODEL}] Tearing down network..."
            teardown_network

            log "  Waiting ${COOLDOWN_BETWEEN_RUNS}s cooldown..."
            sleep "$COOLDOWN_BETWEEN_RUNS"

            # ── Start fresh network ────────────────────────────────────────
            log "  Starting fresh network..."
            if ! startup_network "$cc_name" "$cc_path"; then
                error "  Network startup failed — retrying once..."
                teardown_network; sleep 10
                if ! startup_network "$cc_name" "$cc_path"; then
                    error "  Startup failed twice — skipping run ${run}"
                    echo "${model},${run},0,0,0,0,0,STARTUP_FAILED,${run_start}" >> "${RESULTS_DIR}/failed_runs.log"
                    failed=$(( failed + 1 ))
                    continue
                fi
            fi

            # ── Wait for containers ────────────────────────────────────────
            if ! wait_for_containers; then
                error "  Containers unhealthy — skipping run ${run}"
                failed=$(( failed + 1 ))
                continue
            fi

            # ── Initialize ledger ──────────────────────────────────────────
            init_ledger "$cc_name"

            # ── Generate Caliper network config ────────────────────────────
            generate_network_config "$cc_name"

            # ── Run Caliper (with one retry on failure) ────────────────────
            show_progress "$model" "$run" "$RUNS_PER_MODEL" "Running Caliper..."
            if ! run_caliper "$model" "$run" "$bench_cfg" "$model_dir"; then
                warn "  Run ${run} failed — retrying once..."
                sleep 15
                if ! run_caliper "$model" "$run" "$bench_cfg" "$model_dir"; then
                    error "  Run ${run} failed twice — logging and continuing"
                    echo "${model},${run},FAILED,${run_start}" >> "${RESULTS_DIR}/failed_runs.log"
                    failed=$(( failed + 1 ))
                    completed=$(( completed + 1 ))
                    continue
                fi
            fi

            completed=$(( completed + 1 ))
            local run_end; run_end=$(date '+%Y-%m-%d %H:%M:%S')
            show_progress "$model" "$run" "$RUNS_PER_MODEL" "Done ✓"
            log "  [${model} Run ${run}] Start: ${run_start} | End: ${run_end}"
            log "  Progress: ${completed}/${total_runs} runs completed (${failed} failed)"
        done

        log "✓ MODEL ${model} complete — ${RUNS_PER_MODEL} runs done"
    done

    # ── Aggregate all results into CSV ─────────────────────────────────────
    step "Aggregating Results"
    aggregate_csv

    # ── Final summary ──────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   ALL RUNS COMPLETE                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  Total Runs   : ${total_runs}"
    echo "  Completed    : ${completed}"
    echo "  Failed       : ${failed}"
    echo "  CSV Output   : ${CSV_FILE}"
    echo "  Master Log   : ${MASTER_LOG}"
    echo "  Finished At  : $(date '+%Y-%m-%d %H:%M:%S')"
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
main "$@"
