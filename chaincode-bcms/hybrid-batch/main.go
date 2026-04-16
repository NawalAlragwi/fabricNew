// ============================================================================
//  BCMS Hybrid-Batch Chaincode - Entry Point
//  Branch: mirage-batch
// ============================================================================

package main

import (
	"log"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"github.com/NawalAlragwi/fabricNew/chaincode-bcms/hybrid-batch/chaincode"
)

func main() {
	cc, err := contractapi.NewChaincode(&chaincode.SmartContract{})
	if err != nil {
		log.Panicf("Error creating BCMS hybrid-batch chaincode: %v", err)
	}

	if err := cc.Start(); err != nil {
		log.Panicf("Error starting BCMS hybrid-batch chaincode: %v", err)
	}
}
