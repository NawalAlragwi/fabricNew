// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Entry Point — BLAKE3 Mode
//
//  Research Paper: "Enhancing Trust and Transparency in Education Using
//                   Blockchain: A Hyperledger Fabric-Based Framework"
//
//  This binary starts the BLAKE3-only chaincode peer server.
//  Deploy with:
//    HASH_MODE=blake3 ./chaincode-server
// ============================================================================

package main

import (
	"log"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		log.Panicf("Error creating BLAKE3 BCMS chaincode: %v", err)
	}

	if err := chaincode.Start(); err != nil {
		log.Panicf("Error starting BLAKE3 BCMS chaincode: %v", err)
	}
}
