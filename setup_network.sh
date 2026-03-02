#!/bin/bash
set -e

echo "Starting Fabric Network Setup..."

# Auto-detect root directory from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Download Fabric tools if not present
if [ ! -d "bin" ]; then
    echo "Downloading Fabric tools (Binaries)..."
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
    echo "Fabric tools already present."
fi

export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# 2. Fix permissions
echo "Fixing execute permissions..."
chmod -R +x . 2>/dev/null || true

# 3. Start the network
cd test-network || { echo "ERROR: test-network directory not found!"; exit 1; }

echo "Cleaning up old network..."
./network.sh down

echo "Starting network and creating channel..."
./network.sh up createChannel -c mychannel -ca -s couchdb

echo "Waiting 20 seconds for network to stabilize..."
sleep 20

echo "Network setup complete!"
echo ""
echo "Next steps:"
echo "  1. Deploy chaincode:"
echo "     cd test-network && ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go -ccep \"OR('Org1MSP.peer','Org2MSP.peer')\""
echo "  2. Run Caliper benchmark:"
echo "     cd ../caliper-workspace && ./fix_and_run_caliper.sh"
