// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Entry Point — Hybrid Mode (mirage branch)
//
//  Research Paper: "Enhancing Trust and Transparency in Education Using
//                   Blockchain: A Hyperledger Fabric-Based Framework"
//
//  Chaincode: bcms-hybrid
//  Hash:      Hybrid SHA-256 XOR BLAKE3 (both algorithms, XOR-combined)
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
