#!/usr/bin/env bash
ROOT_DIR="/mnt/c/Users/USERW/pro1/fabricNew"
CC_NAME="bcms-hybrid"

ORG1_BASE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp"
ORG2_BASE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp"

ORG1_KEY=$(find "${ORG1_BASE}/keystore" -type f -name '*_sk' | head -1)
ORG2_KEY=$(find "${ORG2_BASE}/keystore" -type f -name '*_sk' | head -1)
ORG1_CERT="${ORG1_BASE}/signcerts/cert.pem"
ORG2_CERT="${ORG2_BASE}/signcerts/cert.pem"

echo "Org1 key: $ORG1_KEY"
echo "Org2 key: $ORG2_KEY"

mkdir -p "${ROOT_DIR}/caliper-workspace/networks"

sed \
  -e "s|{{ORG1_USER1_PRIVATE_KEY}}|${ORG1_KEY}|g" \
  -e "s|{{ORG2_USER1_PRIVATE_KEY}}|${ORG2_KEY}|g" \
  -e "s|{{ORG1_USER1_SIGNED_CERT}}|${ORG1_CERT}|g" \
  -e "s|{{ORG2_USER1_SIGNED_CERT}}|${ORG2_CERT}|g" \
  -e "s|id: basic|id: ${CC_NAME}|g" \
  "${ROOT_DIR}/caliper-workspace/networkConfig_template.yaml" \
  > "${ROOT_DIR}/caliper-workspace/networks/networkConfig.yaml"

echo "✓ Generated networkConfig.yaml:"
cat "${ROOT_DIR}/caliper-workspace/networks/networkConfig.yaml"
