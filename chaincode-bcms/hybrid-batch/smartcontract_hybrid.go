package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"lukechampine.com/blake3"
)

// ─── 1. تعريف الهياكل (Data Models) ───────────────────────────────────────

// SmartContract يمثل العقد الذكي الأساسي
type SmartContract struct {
	contractapi.Contract
}

// Certificate يمثل بنية الشهادة الأكاديمية
type Certificate struct {
	ID          string `json:"id"`
	StudentID   string `json:"student_id"`
	StudentName string `json:"student_name"`
	Degree      string `json:"degree"`
	Issuer      string `json:"issuer"`
	IssueDate   string `json:"issue_date"`
	CertHash    string `json:"cert_hash"`
	HashAlgo    string `json:"hash_algo"`
	IsRevoked   bool   `json:"is_revoked"`
	DocType     string `json:"doc_type"`
	CreatedAt   string `json:"created_at"`
	UpdatedAt   string `json:"updated_at"`
	TxID        string `json:"tx_id"`
}

// VerificationResult يمثل نتيجة عملية التحقق
type VerificationResult struct {
	CertID    string `json:"cert_id"`
	Valid     bool   `json:"valid"`
	HashMatch bool   `json:"hash_match"`
	IsRevoked bool   `json:"is_revoked"`
	HashAlgo  string `json:"hash_algo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

// ─── 2. منطق التشفير الهجين (Hybrid Hash) ──────────────────────────────────

// ComputeHybridHash يجمع بين SHA-256 و BLAKE3 لحماية الشهادة
func ComputeHybridHash(studentID, studentName, degree, issuer, issueDate string) string {
	data := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")
	
	// الطبقة 1: SHA-256 (للمعيارية)
	h1 := sha256.Sum256([]byte(data))
	
	// الطبقة 2: BLAKE3 (للسرعة والحصانة الأمنية)
	h2 := blake3.Sum256(h1[:])
	
	return fmt.Sprintf("%x", h2)
}

// ─── 3. وظائف العقد الذكي (Smart Contract Functions) ────────────────────────

// IssueCertificateBatch معالجة دفعات من الشهادات في معاملة واحدة (لتحسين الأداء)
func (s *SmartContract) IssueCertificateBatch(ctx contractapi.TransactionContextInterface, certsJSON string) error {
	// التحقق من الهوية (Access Control)
	mspID, _ := ctx.GetClientIdentity().GetMSPID()
	if mspID != "Org1MSP" {
		return fmt.Errorf("unauthorized: only Org1 can issue batches")
	}

	var certs []Certificate
	if err := json.Unmarshal([]byte(certsJSON), &certs); err != nil {
		return fmt.Errorf("failed to parse batch: %v", err)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	txID := ctx.GetStub().GetTxID()

	for _, cert := range certs {
		cert.CertHash = ComputeHybridHash(cert.StudentID, cert.StudentName, cert.Degree, cert.Issuer, cert.IssueDate)
		cert.HashAlgo = "hybrid-sha256-blake3"
		cert.IsRevoked = false
		cert.DocType = "certificate"
		cert.CreatedAt = now
		cert.UpdatedAt = now
		cert.TxID = txID

		certJSON, _ := json.Marshal(cert)
		if err := ctx.GetStub().PutState(cert.ID, certJSON); err != nil {
			return fmt.Errorf("failed to write cert %s: %v", cert.ID, err)
		}
	}
	return nil
}

// VerifyCertificateHybrid التحقق من صحة الشهادة باستخدام الهاش الهجين
func (s *SmartContract) VerifyCertificateHybrid(ctx contractapi.TransactionContextInterface, id string, inputHash string) (*VerificationResult, error) {
	certBytes, _ := ctx.GetStub().GetState(id)
	if certBytes == nil {
		return &VerificationResult{Valid: false, Message: "Certificate Not Found"}, nil
	}

	var cert Certificate
	json.Unmarshal(certBytes, &cert)

	hashMatch := cert.CertHash == inputHash
	
	return &VerificationResult{
		CertID:    id,
		Valid:     hashMatch && !cert.IsRevoked,
		HashMatch: hashMatch,
		IsRevoked: cert.IsRevoked,
		HashAlgo:  cert.HashAlgo,
		Message:   "Verified via Hybrid Cryptography System",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}, nil
}

// QueryAllCertificates جلب جميع الشهادات من الدفتر
// Optimized: Returns only essential fields to reduce payload size
func (s *SmartContract) QueryAllCertificates(ctx contractapi.TransactionContextInterface) (interface{}, error) {
	// RangeQuery on all certificates — returns Iterator
	iterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("failed to get state range: %v", err)
	}
	defer iterator.Close()

	// Return minimal data to reduce size & improve performance
	var certificates []map[string]interface{}

	for iterator.HasNext() {
		response, err := iterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate: %v", err)
		}

		var certData map[string]interface{}
		err = json.Unmarshal(response.Value, &certData)
		if err != nil {
			// Skip invalid entries
			continue
		}

		// Filter only certificates
		if docType, ok := certData["doc_type"]; ok && docType == "certificate" {
			// Return essential fields only (not full cert data)
			minimal := map[string]interface{}{
				"id": certData["id"],
				"student_id": certData["student_id"],
				"is_revoked": certData["is_revoked"],
			}
			certificates = append(certificates, minimal)
		}
	}

	// Return empty array (never nil) when no certs found
	if certificates == nil {
		certificates = make([]map[string]interface{}, 0)
	}

	return certificates, nil
}

// ─── 4. نقطة انطلاق العقد الذكي (Main Entry Point) ──────────────────────────

func main() {
	bcmsChaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		fmt.Printf("Error creating BCMS chaincode: %s", err.Error())
		return
	}

	if err := bcmsChaincode.Start(); err != nil {
		fmt.Printf("Error starting BCMS chaincode: %s", err.Error())
	}
}