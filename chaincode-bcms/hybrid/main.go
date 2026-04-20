// ============================================================================
//  BCMS Hybrid Chaincode — Entry Point (Scenario S3)
//  Single certificate per transaction, SHA-256 on-chain + BLAKE3 advisory.
// ============================================================================

package main

import (
	"log"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"github.com/NawalAlragwi/fabricNew/chaincode-bcms/hybrid/chaincode"
)

func main() {
	cc, err := contractapi.NewChaincode(&chaincode.SmartContract{})
	if err != nil {
		log.Panicf("Error creating BCMS hybrid (S3) chaincode: %v", err)
	}

	if err := cc.Start(); err != nil {
		log.Panicf("Error starting BCMS hybrid (S3) chaincode: %v", err)
	}
}
