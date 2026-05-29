#!/usr/bin/env bash

# ═══════════════════════════════════════════════
# BCMS FINAL RESEARCH PIPELINE (FULL VERSION)
# ═══════════════════════════════════════════════

# ─────────────────────────────────────────────
# Bash check
# ─────────────────────────────────────────────
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  echo "ERROR: Bash 4+ required"
  exit 1
fi

set -euo pipefail

# ─────────────────────────────────────────────
# Scenario Mapping (FIXED 🔥)
# ─────────────────────────────────────────────
declare -A SCENARIO_CCID=(
  [1]="bcms-sha256"
  [2]="bcms-blake3"
  [3]="bcms-hybrid"
  [4]="bcms-hybrid-batch"
)

declare -A SCENARIO_CHAINCODE=(
  [1]="chaincode-bcms/sha256"
  [2]="chaincode-bcms/blake3"
  [3]="chaincode-bcms/hybrid"
  [4]="chaincode-bcms/hybrid-batch"
)

declare -A SCENARIO_BENCHCONFIG=(
  [1]="benchConfig_s1_sha256.yaml"
  [2]="benchConfig_s2_blake3.yaml"
  [3]="benchConfig_s3_hybrid.yaml"
  [4]="benchConfig_s4_hybrid_batch.yaml"
)

TPS_VALUES=(50 100 200)

ROOT_DIR="$(pwd)"
LOG_FILE="run_$(date +%Y%m%d_%H%M%S).log"

log(){ echo "[INFO] $*" | tee -a "$LOG_FILE"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG_FILE"; }

# ─────────────────────────────────────────────
# CPU Compatibility
# ─────────────────────────────────────────────
if grep -q avx2 /proc/cpuinfo 2>/dev/null; then
  export GOAMD64="v3"
fi

# ─────────────────────────────────────────────
# Peer Environment (required for peer CLI)
# ─────────────────────────────────────────────
set_peer_env(){
  export FABRIC_CFG_PATH="${ROOT_DIR}/config"
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_LOCALMSPID="Org1MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
  export CORE_PEER_MSPCONFIGPATH="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
  export CORE_PEER_ADDRESS=localhost:7051
}

# ─────────────────────────────────────────────
# Warm-up
# ─────────────────────────────────────────────
wait_for_chaincode_image(){
  set_peer_env
  log "Warming up chaincode ($CC_NAME)..."
  local CTOR='{"Args":["GetHashAlgorithm"]}'
  for i in {1..15}; do
    if peer chaincode query -C mychannel -n "$CC_NAME" -c "$CTOR" >/dev/null 2>&1; then
      log "Chaincode ready"
      return
    fi
    log "  attempt $i/15 — waiting 6s..."
    sleep 6
  done
  log "Chaincode not ready after 90s — aborting"; exit 1
}

# ─────────────────────────────────────────────
# Peer Health
# ─────────────────────────────────────────────
verify_peers(){
  set_peer_env
  local CTOR='{"Args":["GetHashAlgorithm"]}'
  result=$(peer chaincode query -C mychannel -n "$CC_NAME" -c "$CTOR" 2>&1 || true)

  if echo "$result" | grep -qi error; then
    warn "Restarting peers..."
    docker restart peer0.org1.example.com peer0.org2.example.com
    sleep 10
  fi
}

# ─────────────────────────────────────────────
# Setup Fabric Network
# ─────────────────────────────────────────────
setup_network(){
  local s="$1"

  CC_NAME="${SCENARIO_CCID[$s]}"
  CC_PATH="${SCENARIO_CHAINCODE[$s]}"

  log "Setup Fabric for Scenario $s ($CC_NAME)"

  cd test-network
  ./network.sh down || true

  docker rm -f $(docker ps -aq) 2>/dev/null || true
  docker rmi -f $(docker images | grep dev-peer | awk '{print $3}') 2>/dev/null || true

  ./network.sh up createChannel -c mychannel -ca

  ./network.sh deployCC \
    -ccn "$CC_NAME" \
    -ccp "../$CC_PATH" \
    -ccl go

  cd ..

  # Generate fresh networkConfig.yaml with actual key paths
  generate_network_config

  wait_for_chaincode_image
}

# ─────────────────────────────────────────────
# Generate networkConfig.yaml (DYNAMIC KEY RESOLUTION)
# ─────────────────────────────────────────────
generate_network_config(){
  local ORG1_BASE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp"
  local ORG2_BASE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp"

  # Dynamically find the actual private key (filename changes each network restart)
  local ORG1_KEY; ORG1_KEY=$(find "${ORG1_BASE}/keystore" -type f -name '*_sk' | head -1)
  local ORG2_KEY; ORG2_KEY=$(find "${ORG2_BASE}/keystore" -type f -name '*_sk' | head -1)
  local ORG1_CERT="${ORG1_BASE}/signcerts/cert.pem"
  local ORG2_CERT="${ORG2_BASE}/signcerts/cert.pem"

  if [[ -z "$ORG1_KEY" || ! -f "$ORG1_KEY" ]]; then
    log "ERROR: Org1 private key not found in ${ORG1_BASE}/keystore"; exit 1
  fi
  if [[ -z "$ORG2_KEY" || ! -f "$ORG2_KEY" ]]; then
    log "ERROR: Org2 private key not found in ${ORG2_BASE}/keystore"; exit 1
  fi

  log "Generating networkConfig.yaml..."
  log "  Org1 key: $ORG1_KEY"
  log "  Org2 key: $ORG2_KEY"
  log "  Chaincode ID: $CC_NAME"

  sed \
    -e "s|{{ORG1_USER1_PRIVATE_KEY}}|${ORG1_KEY}|g" \
    -e "s|{{ORG2_USER1_PRIVATE_KEY}}|${ORG2_KEY}|g" \
    -e "s|{{ORG1_USER1_SIGNED_CERT}}|${ORG1_CERT}|g" \
    -e "s|{{ORG2_USER1_SIGNED_CERT}}|${ORG2_CERT}|g" \
    -e "s|id: basic|id: ${CC_NAME}|g" \
    "${ROOT_DIR}/caliper-workspace/networkConfig_template.yaml" \
    > "${ROOT_DIR}/caliper-workspace/networks/networkConfig.yaml"

  log "networkConfig.yaml generated ✓"
}

# ─────────────────────────────────────────────
# Run Caliper
# ─────────────────────────────────────────────
run_caliper(){
  local s="$1"
  local tps="$2"

  CC_NAME="${SCENARIO_CCID[$s]}"
  BENCH="${SCENARIO_BENCHCONFIG[$s]}"

  verify_peers

  cd caliper-workspace

  npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/$BENCH \
    --caliper-flow-only-test

  cd ..
}

# ─────────────────────────────────────────────
# Hash Benchmark (🔥 مهم جدًا)
# ─────────────────────────────────────────────
run_hash_benchmark(){
  log "Running Hash Benchmark..."
  python3 benchmark/python/hash_benchmark.py \
    --output results/hash.json
}

# ─────────────────────────────────────────────
# Tamarin Verification
# ─────────────────────────────────────────────
run_tamarin(){
  log "Running Tamarin..."
  tamarin-prover --prove security/tamarin/model.spthy \
    > results/tamarin.txt || warn "Tamarin failed"
}

# ─────────────────────────────────────────────
# Reports
# ─────────────────────────────────────────────
generate_reports(){
  log "Generating Reports..."

  python3 aggregate_results.py
  python3 generate_four_scenario_report.py
  python3 generate_individual_reports.py
}

# ─────────────────────────────────────────────
# Run Scenario
# ─────────────────────────────────────────────
run_scenario(){
  local s="$1"

  setup_network "$s"

  for tps in "${TPS_VALUES[@]}"; do
    run_caliper "$s" "$tps"
  done
}

# ─────────────────────────────────────────────
# Run All
# ─────────────────────────────────────────────
run_all(){
  for s in 1 2 3 4; do
    run_scenario "$s"
  done
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
mkdir -p results

case "${1:-}" in
  --all)
    run_hash_benchmark
    run_tamarin
    run_all
    generate_reports
    ;;
  1|2|3|4)
    run_scenario "$1"
    ;;
  *)
    echo "Usage:"
    echo "  ./script.sh --all"
    echo "  ./script.sh 1"
    ;;
esac