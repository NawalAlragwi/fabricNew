// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Entry Point — BLAKE3 Mode
// ============================================================================
package main

import (
	"fmt"
	"log"
	"os"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"github.com/NawalAlragwi/fabricNew/chaincode-bcms/blake3/chaincode" // المسار للمجلد الفرعي
)

func main() {
	// إنشاء نسخة من العقد الذكي الموجود في الحزمة الفرعية
	smartContract := new(chaincode.SmartContract)

	// إعداد العقد الذكي الجديد
	cc, err := contractapi.NewChaincode(smartContract)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating BCMS BLAKE3 chaincode: %v\n", err)
		os.Exit(1)
	}

	// تشغيل العقد الذكي
	log.Println("Starting BCMS BLAKE3 chaincode...")
	if err := cc.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "Error starting BCMS BLAKE3 chaincode: %v\n", err)
		os.Exit(1)
	}
}