#!/bin/bash
set -e

ROOT_DIR="/mnt/c/Users/USERW/pro1/fabricNew"
cd "$ROOT_DIR" || cd "/c/Users/USERW/pro1/fabricNew" || cd "c:/Users/USERW/pro1/fabricNew"

TPS_ARRAY=(50 100 150 200 250)
NETWORK_CONFIG="networks/networkConfig.yaml"

cd caliper-workspace
mkdir -p reports/hybrid_v2

for tps in "${TPS_ARRAY[@]}"; do
    echo "==============================================="
    echo " RESTARTING NETWORK BEFORE TPS ${tps}..."
    echo "==============================================="
    # Restart all peers and orderers
    docker restart $(docker ps -q --filter name=peer0.org1 --filter name=peer0.org2 --filter name=orderer) > /dev/null || true
    echo "Waiting 30 seconds for network to stabilize..."
    sleep 30

    echo "==============================================="
    echo " RUNNING HYBRID S3 AT ${tps} TPS"
    echo "==============================================="
    
    BENCH_CONFIG="All_benchmarks/hybrid/bcms-s-hybrid-tps${tps}.yaml"
    
    if [ ! -f "$BENCH_CONFIG" ]; then
        echo "Error: $BENCH_CONFIG not found! Skipping..."
        continue
    fi

    npx caliper launch manager \
      --caliper-workspace . \
      --caliper-networkconfig "$NETWORK_CONFIG" \
      --caliper-benchconfig "$BENCH_CONFIG" \
      --caliper-flow-only-test

    cp report.html reports/hybrid_v2/report_hybrid_tps${tps}.html
    echo "Finished TPS ${tps}. Report saved to reports/hybrid_v2/report_hybrid_tps${tps}.html"
done

echo "==============================================="
echo " ALL TESTS COMPLETED SUCESSFULLY"
echo "==============================================="
