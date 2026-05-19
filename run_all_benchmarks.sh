#!/usr/bin/env bash
# =============================================================================
#  run_all_benchmarks.sh — BCMS 40-Run Benchmark Automation
#  4 Models × 10 Runs | Hyperledger Fabric v2.5 | Caliper v0.5.0
#  Usage: chmod +x run_all_benchmarks.sh && ./run_all_benchmarks.sh
# =============================================================================
set -uo pipefail

# =============================================================================
#  القسم 1: المتغيرات القابلة للتعديل
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK_DIR="${SCRIPT_DIR}/test-network"
CALIPER_WORKSPACE="${SCRIPT_DIR}/caliper-workspace"
RESULTS_DIR="${SCRIPT_DIR}/results/40runs"

# ملفات bench config الفعلية الموجودة في مشروعك
declare -A MODEL_BENCH=(
    [M1]="benchmarks/benchConfig_s1_sha256_tps200.yaml"
    [M2]="benchmarks/benchConfig_s2_blake3_tps200.yaml"
    [M3]="benchmarks/benchConfig_s3_hybrid.yaml"
    [M4]="benchmarks/benchConfig_s4_hybrid_batch.yaml"
)
declare -A MODEL_CCNAME=(
    [M1]="bcms-sha256"
    [M2]="bcms-blake3"
    [M3]="bcms-hybrid"
    [M4]="bcms-hybrid-batch"
)
declare -A MODEL_CCPATH=(
    [M1]="chaincode-bcms/sha256"
    [M2]="chaincode-bcms/blake3"
    [M3]="chaincode-bcms/hybrid"
    [M4]="chaincode-bcms/hybrid-batch"
)

RUNS_PER_MODEL=5   # كان 10
TEARDOWN_WAIT=30
STARTUP_WAIT=60
HEALTH_TIMEOUT=120
MAX_RETRIES=1

# =============================================================================
#  القسم 2: الألوان والطباعة
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[$(date '+%H:%M:%S')] [INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] [OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARN]${NC}   $*"; }
log_error()   { echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $*" >&2; }

show_progress() {
    local model="$1" current="$2" total="$3" elapsed="$4"
    local pct=$(( current * 100 / total ))
    local filled=$(( pct * 20 / 100 )) bar="" i
    for ((i=0; i<20; i++)); do
        [ $i -lt $filled ] && bar+="█" || bar+="░"
    done
    echo -e "${CYAN}${BOLD}  ▶ [${model} | Run ${current}/${total}] [${bar}] ${pct}% | ${elapsed}${NC}"
}

# =============================================================================
#  القسم 3: إدارة شبكة Fabric (network.sh — بنيتك الفعلية)
# =============================================================================
teardown_network() {
    log_info "Tearing down Fabric network..."
    # أوقف chaincode containers أولاً
    docker ps --format '{{.Names}}' 2>/dev/null | grep "^dev-peer" | \
        xargs -r docker stop 2>/dev/null || true
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep "^dev-peer" | \
        xargs -r docker rm -f 2>/dev/null || true
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^dev-peer" | \
        xargs -r docker rmi -f 2>/dev/null || true
    cd "${NETWORK_DIR}"
    ./network.sh down 2>&1 || true
    docker volume prune -f 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    cd "${SCRIPT_DIR}"
    log_info "Waiting ${TEARDOWN_WAIT}s after teardown..."
    sleep "${TEARDOWN_WAIT}"
}

startup_network() {
    local cc_name="$1" cc_path="$2"
    log_info "Starting Fabric network (chaincode: ${cc_name})..."
    cd "${NETWORK_DIR}"
    ./network.sh up createChannel -c mychannel -ca -s couchdb 2>&1 || {
        log_error "Network startup failed"; cd "${SCRIPT_DIR}"; return 1
    }
    export GOFLAGS="-mod=vendor" GOWORK="off" GOPROXY="off"
    ./network.sh deployCC \
        -ccn "${cc_name}" -ccp "${SCRIPT_DIR}/${cc_path}" \
        -ccl go -c mychannel \
        -ccep "OR('Org1MSP.peer','Org2MSP.peer')" 2>&1 || {
        log_error "Chaincode deployment failed"; cd "${SCRIPT_DIR}"; return 1
    }
    cd "${SCRIPT_DIR}"
    log_info "Waiting ${STARTUP_WAIT}s for stabilization..."
    sleep "${STARTUP_WAIT}"
}

wait_for_healthy_containers() {
    log_info "Checking container health (timeout: ${HEALTH_TIMEOUT}s)..."
    local required=("orderer.example.com" "peer0.org1.example.com"
                    "peer0.org2.example.com" "couchdb0" "couchdb1")
    local start elapsed
    start=$(date +%s)
    while true; do
        elapsed=$(( $(date +%s) - start ))
        local all_ok=true
        for c in "${required[@]}"; do
            local st
            st=$(docker inspect --format='{{.State.Status}}' "${c}" 2>/dev/null || echo "missing")
            [ "${st}" = "running" ] || { all_ok=false; break; }
        done
        $all_ok && { log_success "All containers running!"; return 0; }
        (( elapsed >= HEALTH_TIMEOUT )) && {
            log_error "Containers not healthy after ${HEALTH_TIMEOUT}s"
            docker ps --format "table {{.Names}}\t{{.Status}}" || true
            return 1
        }
        log_info "  Waiting... (${elapsed}/${HEALTH_TIMEOUT}s)"
        sleep 10
    done
}

# =============================================================================
#  القسم 4: تهيئة Ledger والـ Caliper network config
# =============================================================================
init_ledger_and_config() {
    local cc_name="$1"
    export PATH="${SCRIPT_DIR}/bin:$PATH"
    export FABRIC_CFG_PATH="${SCRIPT_DIR}/config/"
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE="${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
    export CORE_PEER_ADDRESS=localhost:7051

    # Warm-up: انتظر حتى يستجيب الـ chaincode
    local attempt=1
    while [ $attempt -le 10 ]; do
        peer chaincode query -C mychannel -n "${cc_name}" \
            -c '{"Args":["QueryAllCertificates","5",""]}' 2>/dev/null && break
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
        -c '{"function":"InitLedger","Args":[]}' 2>&1 || log_warn "InitLedger warning (non-fatal)"

    # Caliper network config
    local P1 P2 OT U1K U1C U2K U2C
    P1=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com" -name "ca.crt" | grep "peer0.org1" | head -1)
    P2=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org2.example.com" -name "ca.crt" | grep "peer0.org2" | head -1)
    OT=$(find "${NETWORK_DIR}/organizations/ordererOrganizations" -name "*.pem" | grep "tlsca" | head -1)
    U1K=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore" \( -name "*_sk" -o -name "*.pem" \) 2>/dev/null | head -1)
    U1C=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts" -name "*.pem" 2>/dev/null | head -1)
    U2K=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore" \( -name "*_sk" -o -name "*.pem" \) 2>/dev/null | head -1)
    U2C=$(find "${NETWORK_DIR}/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts" -name "*.pem" 2>/dev/null | head -1)

    mkdir -p "${CALIPER_WORKSPACE}/networks"
    cat > "${CALIPER_WORKSPACE}/networks/connection-org1.yaml" << EOF
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
    grpcOptions: { ssl-target-name-override: orderer.example.com }
    tlsCACerts: { path: '${OT}' }
peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      grpc.keepalive_time_ms: 120000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts: { path: '${P1}' }
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      grpc.keepalive_time_ms: 120000
      grpc.keepalive_timeout_ms: 20000
    tlsCACerts: { path: '${P2}' }
EOF

    cat > "${CALIPER_WORKSPACE}/networks/networkConfig.yaml" << EOF
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
          clientPrivateKey: { path: '${U1K}' }
          clientSignedCert:  { path: '${U1C}' }
    connectionProfile: { path: 'networks/connection-org1.yaml', discover: false }
  - mspid: Org2MSP
    identities:
      certificates:
        - name: 'User1@org2.example.com'
          clientPrivateKey: { path: '${U2K}' }
          clientSignedCert:  { path: '${U2C}' }
    connectionProfile: { path: 'networks/connection-org2.yaml', discover: false }
EOF
    log_success "Network config generated for: ${cc_name}"
}

# =============================================================================
#  القسم 5: تشغيل Caliper لـ run واحد
# =============================================================================
run_caliper_benchmark() {
    local model="$1" bench_cfg="$2" prefix="$3"
    local log_out="${prefix}.caliper.log"

    rm -f "${CALIPER_WORKSPACE}/report.html" "${CALIPER_WORKSPACE}/caliper.log" 2>/dev/null || true
    cd "${CALIPER_WORKSPACE}"

    NO_PROXY="localhost,127.0.0.1" no_proxy="localhost,127.0.0.1" \
    http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" \
    CALIPER_FABRIC_TIMEOUT_INVOKEORQUERY=120000 \
    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig networks/networkConfig.yaml \
        --caliper-benchconfig "${bench_cfg}" \
        --caliper-flow-only-test \
        2>&1 | tee "${log_out}"

    local rc=${PIPESTATUS[0]}
    cd "${SCRIPT_DIR}"

    if [ -f "${CALIPER_WORKSPACE}/report.html" ]; then
        cp "${CALIPER_WORKSPACE}/report.html" "${prefix}_report.html"
        log_success "Report saved: ${prefix}_report.html"
        return 0
    else
        log_error "No report.html (exit: ${rc})"
        cp "${log_out}" "${prefix}.FAILED.log" 2>/dev/null || true
        return 1
    fi
}

# =============================================================================
#  القسم 6: استخراج المقاييس من HTML report
# =============================================================================
extract_metrics() {
    local report="$1" model="$2" run="$3"
    python3 - "${report}" "${model}" "${run}" << 'PYEOF'
import sys, re, json

report_file, model, run = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(report_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Caliper HTML embeds results in a JS variable or table
    # Extract all numeric table cells
    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', content, re.DOTALL)
    tps = avg_lat = max_lat = min_lat = succ = 0.0

    for row in rows:
        cells = re.findall(r'<td[^>]*>([\d.]+)</td>', row)
        if len(cells) >= 5:
            try:
                tps     = float(cells[0])
                avg_lat = float(cells[1])
                min_lat = float(cells[2])
                max_lat = float(cells[3])
                succ    = float(cells[4])
                break
            except ValueError:
                continue

    # Fallback: search for TPS in text
    if tps == 0:
        m = re.search(r'(\d+\.?\d*)\s*(?:TPS|tps)', content)
        if m: tps = float(m.group(1))

    print(f"{model},{run},{tps:.4f},{avg_lat:.6f},{max_lat:.6f},{min_lat:.6f},{succ:.2f}")

except Exception as e:
    print(f"{model},{run},0,0,0,0,0", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# =============================================================================
#  القسم 7: التحقق من المتطلبات
# =============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    local missing=0
    for tool in docker python3 npx peer; do
        command -v "${tool}" &>/dev/null \
            && log_success "  ${tool} ✓" \
            || { log_error "  ${tool} NOT FOUND"; (( missing++ )); }
    done
    [ ! -d "${CALIPER_WORKSPACE}/node_modules/.bin" ] && {
        log_warn "Caliper not installed — running npm install..."
        cd "${CALIPER_WORKSPACE}"
        npm install 2>&1
        npx caliper bind --caliper-bind-sut fabric:2.5 2>&1
        cd "${SCRIPT_DIR}"
    }
    (( missing > 0 )) && { log_error "Fix missing tools and retry."; exit 1; }
    log_success "Prerequisites OK."
}

# =============================================================================
#  القسم 8: حلقة نموذج كامل (10 runs)
# =============================================================================
run_model() {
    local model="$1" csv_file="$2"
    local cc_name="${MODEL_CCNAME[$model]}"
    local cc_path="${MODEL_CCPATH[$model]}"
    local bench_cfg="${MODEL_BENCH[$model]}"
    local model_dir="${RESULTS_DIR}/${model}"
    mkdir -p "${model_dir}"

    local model_start elapsed_fmt
    model_start=$(date +%s)

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  MODEL: ${model} | CC: ${cc_name} | Runs: ${RUNS_PER_MODEL}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    for (( run=1; run<=RUNS_PER_MODEL; run++ )); do
        local elapsed_sec=$(( $(date +%s) - model_start ))
        elapsed_fmt=$(printf '%dh%02dm%02ds' \
            $((elapsed_sec/3600)) $((elapsed_sec%3600/60)) $((elapsed_sec%60)))
        show_progress "${model}" "${run}" "${RUNS_PER_MODEL}" "${elapsed_fmt}"

        local ts prefix
        ts=$(date '+%Y%m%d_%H%M%S')
        prefix="${model_dir}/${model}_run$(printf '%02d' ${run})_${ts}"

        log_info "=== [${model} | Run ${run}/${RUNS_PER_MODEL}] $(date '+%Y-%m-%d %H:%M:%S') ==="

        local attempt=0 run_ok=false
        while (( attempt <= MAX_RETRIES )); do
            (( attempt++ ))
            (( attempt > 1 )) && log_warn "Retry ${attempt}/${MAX_RETRIES}..."

            # 1. Teardown
            teardown_network || log_warn "Teardown warning — continuing"

            # 2. Startup + deploy
            startup_network "${cc_name}" "${cc_path}" || {
                (( attempt <= MAX_RETRIES )) && continue || break
            }

            # 3. Health check
            wait_for_healthy_containers || {
                (( attempt <= MAX_RETRIES )) && continue || break
            }

            # 4. Init ledger + generate config
            init_ledger_and_config "${cc_name}"

            # 5. Run Caliper
            run_caliper_benchmark "${model}" "${bench_cfg}" "${prefix}" && {
                run_ok=true; break
            }
            log_error "Caliper failed on attempt ${attempt}"
            echo "FAILED: ${model} Run ${run} Attempt ${attempt} $(date)" \
                >> "${RESULTS_DIR}/failed_runs.log"
        done

        if $run_ok; then
            log_success "[${model} | Run ${run}] Completed ✓"
            local metrics
            metrics=$(extract_metrics "${prefix}_report.html" "${model}" "${run}" 2>/dev/null \
                      || echo "${model},${run},0,0,0,0,0")
            echo "${metrics}" >> "${csv_file}"
            log_info "  → ${metrics}"
        else
            log_error "[${model} | Run ${run}] SKIPPED after retries"
            echo "${model},${run},NA,NA,NA,NA,NA" >> "${csv_file}"
        fi
        echo ""
    done

    local total_sec=$(( $(date +%s) - model_start ))
    log_success "Model ${model} done in $(printf '%dh%02dm%02ds' \
        $((total_sec/3600)) $((total_sec%3600/60)) $((total_sec%60)))"
}

# =============================================================================
#  القسم 9: main
# =============================================================================
main() {
    local script_start
    script_start=$(date +%s)

    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   BCMS — 40-Run Benchmark Automation  (4 Models × 10 Runs) ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}  Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo    "  Results: ${RESULTS_DIR}"
    echo ""

    check_prerequisites
    mkdir -p "${RESULTS_DIR}"

    local csv_file="${RESULTS_DIR}/all_runs_raw.csv"
    local session_log="${RESULTS_DIR}/session_$(date '+%Y%m%d_%H%M%S').log"
    exec > >(tee -a "${session_log}") 2>&1

    echo "Model,Run,AvgTPS,AvgLatency,MaxLatency,MinLatency,SuccessRate" > "${csv_file}"
    log_info "CSV: ${csv_file} | Log: ${session_log}"

    # M1 مكتملة — تم تشغيل 5 runs مسبقاً
    # run_model "M1" "${csv_file}"
    # run_model "M2" "${csv_file}"
    run_model "M3" "${csv_file}"
    # run_model "M4" "${csv_file}"

    # Final teardown
    log_info "All benchmarks complete — final teardown..."
    teardown_network || true

    # Summary
    local total_sec=$(( $(date +%s) - script_start ))
    local ok_runs failed_runs
    ok_runs=$(tail -n +2 "${csv_file}" | grep -vc "NA" 2>/dev/null || echo 0)
    failed_runs=$(tail -n +2 "${csv_file}" | grep -c "NA" 2>/dev/null || echo 0)

    echo -e "${BOLD}${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    ALL RUNS COMPLETE                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}  Total time  : $(printf '%dh%02dm%02ds' \
        $((total_sec/3600)) $((total_sec%3600/60)) $((total_sec%60)))"
    echo    "  Successful  : ${ok_runs}/40"
    echo    "  Failed      : ${failed_runs}"
    echo    "  CSV         : ${csv_file}"
    echo    "  Session log : ${session_log}"
    echo ""
    echo -e "${BOLD}CSV Preview:${NC}"
    head -9 "${csv_file}" | column -t -s','
    echo ""
}

main "$@"
