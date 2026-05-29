#!/bin/bash
set -euo pipefail
cd /mnt/c/Users/USERW/pro1/fabricNew

# 1. Stop competing chaincode (bcms-sha256) so they don't fight for resources
docker ps --format '{{.Names}}' | grep "dev-peer.*bcms-sha256" | while read c; do docker stop "$c"; done || true

# 2. Deploy bcms-blake3 (with AVX2)
export GOFLAGS="-mod=mod"
export GOWORK="off"
export GO111MODULE="on"
export GOAMD64="v3"
export PATH="${PWD}/bin:$PATH"

cd test-network
rm -f bcms-blake3.tar.gz
./network.sh deployCC -ccn bcms-blake3 -ccp ../chaincode-bcms/blake3 -ccl go -c mychannel -ccep "OR('Org1MSP.peer','Org2MSP.peer')" || { echo "Deploy failed!"; exit 1; }

# 3. Warm up
cd ..
export FABRIC_CFG_PATH="${PWD}/config/"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${PWD}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "${PWD}/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem" -C mychannel -n bcms-blake3 --peerAddresses localhost:7051 --tlsRootCertFiles "${PWD}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" --peerAddresses localhost:9051 --tlsRootCertFiles "${PWD}/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt" -c '{"function":"InitLedger","Args":[]}' || true
sleep 5

peer chaincode query -C mychannel -n bcms-blake3 -c '{"Args":["QueryAllCertificates","5",""]}' || true

# 4. Fix config & Run benchmark
bash fix_network_config.sh
cd caliper-workspace
sed -i 's/bcms-sha256/bcms-blake3/g' networks/networkConfig.yaml

npx caliper launch manager \
  --caliper-workspace . \
  --caliper-benchconfig All_benchmarks/blake3/bcms-s-blake3-tps200.yaml \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-timeout-invokeorquery 120000

mkdir -p reports
cp report.html reports/blake3-tps200-final.html
echo "DONE"
