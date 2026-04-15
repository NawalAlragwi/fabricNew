// ============================================================================
//  BCMS - Blockchain Certificate Management System
//  Chaincode Implementation - SHA-256 Mode
//
//  This implementation uses crypto/sha256 for certificate hashing.
//  Switchable via HASH_MODE=sha256 environment variable.
//
//  HASH_MODE=sha256 (this file)
//  HASH_MODE=blake3 (see ../blake3/smartcontract_blake3.go)
// ============================================================================

package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// HashMode selects which hash algorithm to use
const HashModeSHA256 = "sha256"

// GetHashMode reads HASH_MODE env variable, defaults to sha256
func GetHashMode() string {
	mode := os.Getenv("HASH_MODE")
	if mode == "" {
		return HashModeSHA256
	}
	return strings.ToLower(mode)
}

// --- Data Structures --------------------------------------------------------

// Certificate  core educational record stored on the ledger
type Certificate struct {
	DocType     string `json:"docType"`
	ID          string `json:"id"`
	StudentID   string `json:"studentID"`
	StudentName string `json:"studentName"`
	Degree      string `json:"degree"`
	Issuer      string `json:"issuer"`
	IssueDate   string `json:"issueDate"`
	CertHash    string `json:"certHash"`
	HashAlgo    string `json:"hashAlgo"` // "sha256" or "blake3"
	Signature   string `json:"signature"`
	IsRevoked   bool   `json:"isRevoked"`
	RevokedBy   string `json:"revokedBy"`
	RevokedAt   string `json:"revokedAt"`
	CreatedAt   string `json:"createdAt"`
	UpdatedAt   string `json:"updatedAt"`
	TxID        string `json:"txID"`
}

// VerificationResult  returned by VerifyCertificate
type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	HashAlgo  string `json:"hashAlgo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

// AuditLog  captures mutations for audit trail
type AuditLog struct {
	DocType   string `json:"docType"`
	TxID      string `json:"txID"`
	CertID    string `json:"certID"`
	Action    string `json:"action"` // ISSUE | REVOKE
	Actor     string `json:"actor"`
	Timestamp string `json:"timestamp"`
	Detail    string `json:"detail"`
}

// SmartContract  the main Hyperledger Fabric contract (SHA-256 mode)
type SmartContract struct {
	contractapi.Contract
}

// --- Internal Helpers --------------------------------------------------------

func (s *SmartContract) writeAudit(
	ctx contractapi.TransactionContextInterface,
	certID, action, actor, detail string,
) {
	txID := ctx.GetStub().GetTxID()
	key := fmt.Sprintf("AUDIT_%s_%s", txID, certID)
	log := AuditLog{
		DocType:   "auditLog",
		TxID:      txID,
		CertID:    certID,
		Action:    action,
		Actor:     actor,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Detail:    detail,
	}
	data, _ := json.Marshal(log)
	_ = ctx.GetStub().PutState(key, data)
}

//  SHA-256 Hash Implementation ---

// ComputeCertHashSHA256 computes H(C) = SHA256(studentID|name|degree|issuer|date)
// This is the original BCMS implementation from the research paper.
// Time complexity: O(n) where n = total byte length of certificate fields
// Security: 256-bit output, collision resistance: 2^128, preimage: 2^256
func ComputeCertHashSHA256(studentID, studentName, degree, issuer, issueDate string) string {
	data := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")
	hash := sha256.Sum256([]byte(data))
	return fmt.Sprintf("%x", hash)
}

// ComputeCertHash is the switchable hash function entry point
// Routes to SHA256 or BLAKE3 depending on HASH_MODE environment variable
func ComputeCertHash(studentID, studentName, degree, issuer, issueDate string) (string, string) {
	// In SHA256 mode, always use SHA256
	hash := ComputeCertHashSHA256(studentID, studentName, degree, issuer, issueDate)
	return hash, "sha256"
}

// --- Identity Helpers --------------------------------------------------------

func getCallerMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("failed to read client MSP ID: %v", err)
	}
	return mspID, nil
}

func getCallerRole(ctx contractapi.TransactionContextInterface) string {
	role, found, err := ctx.GetClientIdentity().GetAttributeValue("role")
	if err != nil || !found {
		return ""
	}
	return role
}

// --- Smart Contract Functions ------------------------------------------------

// InitLedger seeds the ledger with sample certificates (SHA-256 mode)
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil || mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can initialize ledger")
	}

	type seedCert struct {
		id, studentID, studentName, degree, issuer, issueDate string
	}
	seeds := []seedCert{
		{"CERT001", "STU001", "Alice Johnson", "Bachelor of Computer Science", "Digital University", "2024-01-15"},
		{"CERT002", "STU002", "Bob Smith", "Master of Data Science", "Tech Institute", "2024-02-20"},
		{"CERT003", "STU003", "Carol Williams", "PhD in Artificial Intelligence", "Research Academy", "2024-03-10"},
		{"CERT004", "STU004", "David Brown", "Bachelor of Engineering", "Engineering College", "2024-04-05"},
		{"CERT005", "STU005", "Eve Davis", "MBA in Business Administration", "Business School", "2024-05-12"},
	}

	for _, seed := range seeds {
		certHash, hashAlgo := ComputeCertHash(seed.studentID, seed.studentName, seed.degree, seed.issuer, seed.issueDate)
		cert := Certificate{
			DocType:     "certificate",
			ID:          seed.id,
			StudentID:   seed.studentID,
			StudentName: seed.studentName,
			Degree:      seed.degree,
			Issuer:      seed.issuer,
			IssueDate:   seed.issueDate,
			CertHash:    certHash,
			HashAlgo:    hashAlgo,
			Signature:   fmt.Sprintf("SIG_%s_%s", seed.id, certHash[:16]),
			IsRevoked:   false,
			CreatedAt:   time.Now().UTC().Format(time.RFC3339),
			UpdatedAt:   time.Now().UTC().Format(time.RFC3339),
			TxID:        ctx.GetStub().GetTxID(),
		}
		certJSON, err := json.Marshal(cert)
		if err != nil {
			return fmt.Errorf("failed to marshal certificate %s: %v", seed.id, err)
		}
		if err := ctx.GetStub().PutState(seed.id, certJSON); err != nil {
			return fmt.Errorf("failed to put certificate %s: %v", seed.id, err)
		}
	}
	return nil
}

// IssueCertificate stores a new certificate on the ledger (SHA-256 mode)
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	studentID string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
	certHash string,
	blake3Hash string, // Added to match workload's 10 args
	signature string,
	batchID string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil || mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can issue certificates")
	}

	existing, _ := ctx.GetStub().GetState(id)
	if existing != nil {
		return nil
	}

	computedHash, hashAlgo := ComputeCertHash(studentID, studentName, degree, issuer, issueDate)
	if certHash == "" {
		certHash = computedHash
	}

	now := time.Now().UTC().Format(time.RFC3339)
	cert := Certificate{
		DocType:     "certificate",
		ID:          id,
		StudentID:   studentID,
		StudentName: studentName,
		Degree:      degree,
		Issuer:      issuer,
		IssueDate:   issueDate,
		CertHash:    certHash,
		HashAlgo:    hashAlgo,
		Signature:   signature,
		IsRevoked:   false,
		CreatedAt:   now,
		UpdatedAt:   now,
		TxID:        ctx.GetStub().GetTxID(),
	}

	certJSON, _ := json.Marshal(cert)
	ctx.GetStub().PutState(id, certJSON)
	
	// Audit log including batch info if needed
	s.writeAudit(ctx, id, "ISSUE", issuer, fmt.Sprintf("SHA-256 issue | Batch: %s", batchID))

	return nil
}

// VerifyCertificate verifies certificate authenticity using SHA-256
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (*VerificationResult, error) {
	ts := time.Now().UTC().Format(time.RFC3339)
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil || certJSON == nil {
		return &VerificationResult{CertID: id, Valid: false, Message: "not found", Timestamp: ts}, nil
	}

	var cert Certificate
	json.Unmarshal(certJSON, &cert)

	res := &VerificationResult{
		CertID: id, IsRevoked: cert.IsRevoked, HashAlgo: "sha256", Timestamp: ts,
		HashMatch: cert.CertHash == certHash,
	}
	res.Valid = res.HashMatch && !cert.IsRevoked
	return res, nil
}

func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	msp, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: %v", err)
	}
	certJSON, _ := ctx.GetStub().GetState(id)
	if certJSON == nil {
		return nil
	}
	var cert Certificate
	json.Unmarshal(certJSON, &cert)

	if cert.IsRevoked {
		return nil
	}

	cert.IsRevoked = true
	cert.RevokedBy = msp
	cert.RevokedAt = time.Now().UTC().Format(time.RFC3339)
	
	updated, _ := json.Marshal(cert)
	ctx.GetStub().PutState(id, updated)
	s.writeAudit(ctx, id, "REVOKE", msp, "SHA-256 revoke")
	return nil
}

func (s *SmartContract) QueryAllCertificates(ctx contractapi.TransactionContextInterface) ([]*Certificate, error) {
	// 1. Starting range scan
	resultsIterator, err := ctx.GetStub().GetStateByRange("CERT_", "CERT_~")
	if err != nil {
		return []*Certificate{}, nil
	}
	defer resultsIterator.Close()

	certificates := make([]*Certificate, 0)
	count := 0
	for resultsIterator.HasNext() && count < 500 { // Safety limit: 500 records
		queryResponse, err := resultsIterator.Next()
		if err != nil { continue }

		var cert Certificate
		err = json.Unmarshal(queryResponse.Value, &cert)
		// 2. Strict validation: check for docType
		if err == nil && cert.DocType == "certificate" {
			certificates = append(certificates, &cert)
			count++
		}
	}
	return certificates, nil
}

func (s *SmartContract) getAllCertificatesByRange(ctx contractapi.TransactionContextInterface) ([]*Certificate, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("CERT_", "CERT_~")
	if err != nil { return []*Certificate{}, nil }
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil { continue }
		var cert Certificate
		json.Unmarshal(queryResponse.Value, &cert)
		if cert.DocType == "certificate" {
			certificates = append(certificates, &cert)
		}
	}
	return certificates, nil
}

func (s *SmartContract) GetCertificatesByStudent(ctx contractapi.TransactionContextInterface, studentID string) ([]*Certificate, error) {
	// Re-added sort and missing selector field to FORCE CouchDB to use the index
	queryString := fmt.Sprintf(`{"selector":{"docType":"certificate","studentID":"%s","issueDate":{"$gt":null}},"sort":[{"issueDate":"desc"}]}`, studentID)
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return []*Certificate{}, nil
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil { continue }
		var cert Certificate
		err = json.Unmarshal(queryResponse.Value, &cert)
		if err == nil {
			certificates = append(certificates, &cert)
		}
	}
	return certificates, nil
}

func (s *SmartContract) getCertificatesByStudentRange(ctx contractapi.TransactionContextInterface, studentID string) ([]*Certificate, error) {
	all, _ := s.getAllCertificatesByRange(ctx)
	filtered := make([]*Certificate, 0)
	for _, c := range all {
		if c.StudentID == studentID {
			filtered = append(filtered, c)
		}
	}
	return filtered, nil
}

func (s *SmartContract) GetAuditLogs(ctx contractapi.TransactionContextInterface) ([]*AuditLog, error) {
	// CouchDB Requirement: Fields in sort must exist in selector to use index
	queryString := `{"selector":{"docType":"auditLog","timestamp":{"$gt":null}},"sort":[{"timestamp":"desc"}]}`
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil || resultsIterator == nil {
		return s.getAuditLogsByRange(ctx)
	}
	defer resultsIterator.Close()

	var logs []*AuditLog
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil { continue }
		var log AuditLog
		err = json.Unmarshal(queryResponse.Value, &log)
		if err == nil {
			logs = append(logs, &log)
		}
	}
	return logs, nil
}

func (s *SmartContract) getAuditLogsByRange(ctx contractapi.TransactionContextInterface) ([]*AuditLog, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("AUDIT_", "AUDIT_~")
	if err != nil { return []*AuditLog{}, nil }
	defer resultsIterator.Close()

	var logs []*AuditLog
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil { continue }
		var log AuditLog
		err = json.Unmarshal(queryResponse.Value, &log)
		if err == nil {
			logs = append(logs, &log)
		}
	}
	return logs, nil
}

// ComputeHash exposes hash computation for benchmarking
func (s *SmartContract) ComputeHash(
	ctx contractapi.TransactionContextInterface,
	studentID string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
) (string, error) {
	if studentID == "" || studentName == "" || degree == "" || issuer == "" || issueDate == "" {
		return "", fmt.Errorf("all fields are required")
	}
	hash, _ := ComputeCertHash(studentID, studentName, degree, issuer, issueDate)
	return hash, nil
}

// GetHashAlgorithm returns the current hash algorithm
func (s *SmartContract) GetHashAlgorithm(
	ctx contractapi.TransactionContextInterface,
) (string, error) {
	return "sha256", nil
}
