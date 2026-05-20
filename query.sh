export FABRIC_CFG_PATH=/mnt/c/Users/USERW/pro1/fabricNew/config/
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_TLS_ROOTCERT_FILE=/mnt/c/Users/USERW/pro1/fabricNew/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=/mnt/c/Users/USERW/pro1/fabricNew/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
export PATH=/mnt/c/Users/USERW/pro1/fabricNew/bin:$PATH
peer chaincode query -C mychannel -n bcms-sha256 -c '{"Args":["QueryAllCertificates", "20", ""]}'
