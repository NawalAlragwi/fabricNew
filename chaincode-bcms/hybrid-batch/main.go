// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Entry Point — Hybrid-Batch Mode (mirage branch)
//
//  Research Paper: "Enhancing Trust and Transparency in Education Using
//                   Blockchain: A Hyperledger Fabric-Based Framework"
//
//  Chaincode: hybrid-batch (no-batch for mirage branch)
//  Hash:      SHA-256 (deterministic, cross-platform consistent)
// ============================================================================

package main

import (
	"log"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"github.com/NawalAlragwi/fabricNew/chaincode-bcms/hybrid-batch/chaincode"
)

func main() {
	chaincode, err := contractapi.NewChaincode(&chaincode.SmartContract{})
	if err != nil {
		log.Panicf("Error creating BCMS hybrid-batch chaincode: %v", err)
	}

	if err := chaincode.Start(); err != nil {
		log.Panicf("Error starting BCMS hybrid-batch chaincode: %v", err)
	}
}
