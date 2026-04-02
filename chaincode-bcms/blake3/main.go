// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Entry Point — BLAKE3 Mode
//
//  Branch: fabric-blake3
//  Algorithm: BLAKE3 (github.com/zeebo/blake3)
// ============================================================================

package main

import (
	"fmt"
	"log"
	"os"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

func main() {
	// Optional: print algorithm info at startup
	fmt.Fprintf(os.Stdout, "[BCMS-BLAKE3] Starting chaincode — HashAlgorithm: BLAKE3\n")

	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		log.Panicf("Error creating BCMS BLAKE3 chaincode: %v", err)
	}

	if err := chaincode.Start(); err != nil {
		log.Panicf("Error starting BCMS BLAKE3 chaincode: %v", err)
	}
}
