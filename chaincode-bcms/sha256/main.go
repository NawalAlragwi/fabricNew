// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Entry Point — SHA-256 Mode
// ============================================================================

package main

import (
	"fmt"
	"os"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	chaincode "github.com/NawalAlragwi/fabricNew/chaincode-bcms/sha256"
)

func main() {
	cc, err := contractapi.NewChaincode(&chaincode.SmartContract{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating BCMS SHA-256 chaincode: %v\n", err)
		os.Exit(1)
	}
	if err := cc.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "Error starting BCMS SHA-256 chaincode: %v\n", err)
		os.Exit(1)
	}
}
