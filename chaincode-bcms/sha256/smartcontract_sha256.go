// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Implementation — SHA-256 Mode
//
//  This implementation uses crypto/sha256 for certificate hashing.
//  Switchable via HASH_MODE=sha256 environment variable.
//
//  HASH_MODE=sha256 (this file)
//  HASH_MODE=blake3 (see ../blake3/smartcontract_blake3.go)
// ============================================================================

package chaincode

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

// ─── Data Structures ────────────────────────────────────────────────────────

// Certificate — core educational record stored on the ledger
type Certificate struct {
	DocType     string `json:"docType"`
	ID          string `json:"ID"`
	StudentID   string `json:"StudentID"`
	StudentName string `json:"StudentName"`
	Degree      string `json:"Degree"`
	Issuer      string `json:"Issuer"`
	IssueDate   string `json:"IssueDate"`
	CertHash    string `json:"CertHash"`
	HashAlgo    string `json:"HashAlgo"` // "sha256" or "blake3"
	Signature   string `json:"Signature"`
	IsRevoked   bool   `json:"IsRevoked"`
	RevokedBy   string `json:"RevokedBy"`
	RevokedAt   string `json:"RevokedAt"`
	CreatedAt   string `json:"CreatedAt"`
	UpdatedAt   string `json:"UpdatedAt"`
	TxID        string `json:"TxID"`
}

// VerificationResult — returned by VerifyCertificate
type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	HashAlgo  string `json:"hashAlgo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

// SmartContract — the main Hyperledger Fabric contract (SHA-256 mode)
type SmartContract struct {
	contractapi.Contract
}

// ─── SHA-256 Hash Implementation ────────────────────────────────────────────

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

// ─── Identity Helpers ────────────────────────────────────────────────────────

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

// ─── Smart Contract Functions ────────────────────────────────────────────────

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
	certHashInput string,
	signature string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("access denied: failed to read MSP: %v", err)
	}
	if mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can issue certificates")
	}

	role := getCallerRole(ctx)
	if role != "" && role != "issuer" {
		return fmt.Errorf("access denied: role attribute must be 'issuer'")
	}

	if id == "" || studentID == "" || studentName == "" || degree == "" || issuer == "" || issueDate == "" {
		return fmt.Errorf("validation error: missing fields")
	}

	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read ledger: %v", err)
	}
	if existing != nil {
		return nil // Idempotent — already exists
	}

	// Compute hash using SHA-256
	computedHash, hashAlgo := ComputeCertHash(studentID, studentName, degree, issuer, issueDate)
	if certHashInput == "" {
		certHashInput = computedHash
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
		CertHash:    certHashInput,
		HashAlgo:    hashAlgo,
		Signature:   signature,
		IsRevoked:   false,
		CreatedAt:   now,
		UpdatedAt:   now,
		TxID:        ctx.GetStub().GetTxID(),
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal certificate: %v", err)
	}

	if err := ctx.GetStub().PutState(id, certJSON); err != nil {
		return fmt.Errorf("failed to write certificate to ledger: %v", err)
	}

	return nil
}

// VerifyCertificate verifies certificate authenticity using SHA-256
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (*VerificationResult, error) {
	ts := time.Now().UTC().Format(time.RFC3339)

	role := getCallerRole(ctx)
	if role != "" && role != "verifier" && role != "issuer" {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "access denied: unauthorized role",
			HashAlgo:  "sha256",
			Timestamp: ts,
		}, nil
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil || certJSON == nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "certificate not found",
			HashAlgo:  "sha256",
			Timestamp: ts,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "data integrity error",
			HashAlgo:  "sha256",
			Timestamp: ts,
		}, nil
	}

	if cert.IsRevoked {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			IsRevoked: true,
			HashMatch: cert.CertHash == certHash,
			HashAlgo:  "sha256",
			Message:   "certificate has been revoked",
			Timestamp: ts,
		}, nil
	}

	hashMatch := cert.CertHash == certHash
	if !hashMatch {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			IsRevoked: false,
			HashMatch: false,
			HashAlgo:  "sha256",
			Message:   "hash mismatch — certificate may have been tampered",
			Timestamp: ts,
		}, nil
	}

	return &VerificationResult{
		CertID:    id,
		Valid:     true,
		IsRevoked: false,
		HashMatch: true,
		HashAlgo:  "sha256",
		Message:   "certificate is valid and authentic (SHA-256 verified)",
		Timestamp: ts,
	}, nil
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
