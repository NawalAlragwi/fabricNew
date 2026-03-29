// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Entry Point — Hybrid-Batch Mode (SHA-256 + BLAKE3)
//
//  BUG-4 FIX: This main.go was missing. Without a main package that calls
//  contractapi.Start(), the Fabric peer CLI command
//    peer lifecycle chaincode package / install / approve / commit
//  fails at compilation with "no main package found".
//
//  Every Go Hyperledger Fabric chaincode MUST have exactly one main.go
//  that calls contractapi.Start(new(chaincode.SmartContract)).
// ============================================================================

package main

import (
	"fmt"
	"os"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

func main() {
	cc, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating BCMS Hybrid-Batch chaincode: %v\n", err)
		os.Exit(1)
	}
	if err := cc.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "Error starting BCMS Hybrid-Batch chaincode: %v\n", err)
		os.Exit(1)
	}
}
