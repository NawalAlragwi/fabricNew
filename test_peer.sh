#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/mnt/c/Users/USERW/pro1/fabricNew"

export FABRIC_CFG_PATH="${ROOT_DIR}/config"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS="localhost:7051"

echo "=== Testing peer connection ==="
echo "FABRIC_CFG_PATH: $FABRIC_CFG_PATH"
echo "CORE_PEER_ADDRESS: $CORE_PEER_ADDRESS"

CTOR='{"Args":["GetHashAlgorithm"]}'
echo "Running: peer chaincode query -C mychannel -n bcms-sha256 -c '$CTOR'"

peer chaincode query -C mychannel -n bcms-sha256 -c "$CTOR"
echo "EXIT: $?"
