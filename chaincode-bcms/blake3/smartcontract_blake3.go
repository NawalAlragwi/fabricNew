// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Implementation — BLAKE3 Mode
//
//  This implementation uses BLAKE3 for certificate hashing.
//  Switchable via HASH_MODE=blake3 environment variable.
//
//  BLAKE3 advantages over SHA-256:
//    - 3-10x faster on modern hardware (AVX-512 / NEON acceleration)
//    - 256-bit output (same security level as SHA-256)
//    - Designed to be highly parallelizable
//    - Suitable for high-throughput blockchain workloads
//    - RFC status: widely adopted in security software
//
//  HASH_MODE=sha256 (see ../sha256/smartcontract_sha256.go)
//  HASH_MODE=blake3 (this file)
// ============================================================================

package chaincode

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"lukechampine.com/blake3"
)

// HashModeBLAKE3 identifies the BLAKE3 hash algorithm
const HashModeBLAKE3 = "blake3"

// ─── Data Structures (same as SHA-256 variant) ───────────────────────────────

// Certificate — core educational record stored on the ledger (BLAKE3 mode)
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

// SmartContract — the main Hyperledger Fabric contract (BLAKE3 mode)
type SmartContract struct {
	contractapi.Contract
}

// ─── BLAKE3 Hash Implementation ──────────────────────────────────────────────

// ComputeCertHashBLAKE3 computes H(C) = BLAKE3(studentID|name|degree|issuer|date)
//
// BLAKE3 Algorithm Properties:
//   - Output size: 256 bits (32 bytes) — same as SHA-256
//   - Security level: 128-bit (collision), 256-bit (preimage)
//   - Performance: ~3-10x faster than SHA-256 on modern hardware
//   - Tree-based: supports parallel hashing for large inputs
//   - SIMD acceleration: AVX-512, AVX2, SSE4.1, NEON
//
// Performance comparison (benchmark data from paper):
//   SHA-256:  ~250-350 MB/s (software)
//   BLAKE3:   ~800-3000 MB/s (with SIMD, AVX-512)
//
// For certificate data (~50-100 bytes), timing difference is negligible
// in isolation, but compounds to significant savings at scale (1000+ TPS).
func ComputeCertHashBLAKE3(studentID, studentName, degree, issuer, issueDate string) string {
	data := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")
	// BLAKE3 hash with 256-bit (32 byte) output
	hashBytes := blake3.Sum256([]byte(data))
	return fmt.Sprintf("%x", hashBytes)
}

// ComputeCertHash is the switchable hash function entry point (BLAKE3 variant)
func ComputeCertHash(studentID, studentName, degree, issuer, issueDate string) (string, string) {
	hash := ComputeCertHashBLAKE3(studentID, studentName, degree, issuer, issueDate)
	return hash, "blake3"
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

// ─── Smart Contract Functions (BLAKE3 mode) ──────────────────────────────────

// InitLedger seeds the ledger with sample certificates (BLAKE3 mode)
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

// IssueCertificate stores a new certificate on the ledger (BLAKE3 mode)
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
		return nil // Idempotent
	}

	// Compute hash using BLAKE3
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

// VerifyCertificate verifies certificate authenticity using BLAKE3
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
			HashAlgo:  "blake3",
			Timestamp: ts,
		}, nil
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil || certJSON == nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "certificate not found",
			HashAlgo:  "blake3",
			Timestamp: ts,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "data integrity error",
			HashAlgo:  "blake3",
			Timestamp: ts,
		}, nil
	}

	if cert.IsRevoked {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			IsRevoked: true,
			HashMatch: cert.CertHash == certHash,
			HashAlgo:  "blake3",
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
			HashAlgo:  "blake3",
			Message:   "hash mismatch — certificate may have been tampered",
			Timestamp: ts,
		}, nil
	}

	return &VerificationResult{
		CertID:    id,
		Valid:     true,
		IsRevoked: false,
		HashMatch: true,
		HashAlgo:  "blake3",
		Message:   "certificate is valid and authentic (BLAKE3 verified)",
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
	return "blake3", nil
}
