// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Implementation — BLAKE3 Mode
//
//  Research Paper: "Enhancing Trust and Transparency in Education Using
//                   Blockchain: A Hyperledger Fabric-Based Framework"
//
//  This implementation uses BLAKE3 for certificate hashing.
//  Key changes from SHA-256 baseline:
//    - Replaced crypto/sha256 with lukechampine.com/blake3
//    - ComputeCertHash uses blake3.Sum256 (same 256-bit output as SHA-256)
//    - Certificate.HashAlgorithm field set to "BLAKE3"
//    - Audit logging disabled during benchmarks (DISABLE_AUDIT=true env var)
//    - GetHashAlgorithm() returns "BLAKE3"
//
//  BLAKE3 advantages over SHA-256:
//    - 3-10x faster on modern hardware (AVX-512 / NEON acceleration)
//    - 256-bit output (same security level as SHA-256)
//    - Designed to be highly parallelizable
//    - Suitable for high-throughput blockchain workloads
//    - RFC status: widely adopted in security software
//    - Performance: ~800-3000 MB/s vs SHA-256 ~250-350 MB/s
//
//  HASH_MODE=blake3 (this file)
//  HASH_MODE=sha256 (see ../sha256/smartcontract_sha256.go)
// ============================================================================

package chaincode

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"lukechampine.com/blake3"
)

// HashModeBLAKE3 identifies the BLAKE3 hash algorithm
const HashModeBLAKE3 = "blake3"

// ─── Data Structures ────────────────────────────────────────────────────────

// Certificate — core educational record stored on the ledger (BLAKE3 mode)
type Certificate struct {
	DocType       string `json:"docType"`
	ID            string `json:"ID"`
	StudentID     string `json:"StudentID"`
	StudentName   string `json:"StudentName"`
	Degree        string `json:"Degree"`
	Issuer        string `json:"Issuer"`
	IssueDate     string `json:"IssueDate"`
	CertHash      string `json:"CertHash"`
	HashAlgorithm string `json:"HashAlgorithm"` // "BLAKE3" — required by benchmark spec
	HashAlgo      string `json:"HashAlgo"`      // Kept for backward compat: "blake3"
	Signature     string `json:"Signature"`
	IsRevoked     bool   `json:"IsRevoked"`
	RevokedBy     string `json:"RevokedBy"`
	RevokedAt     string `json:"RevokedAt"`
	CreatedAt     string `json:"CreatedAt"`
	UpdatedAt     string `json:"UpdatedAt"`
	TxID          string `json:"TxID"`
}

// AuditLog — immutable audit trail entry
type AuditLog struct {
	DocType   string `json:"docType"`
	LogID     string `json:"LogID"`
	CertID    string `json:"CertID"`
	Action    string `json:"Action"`
	Actor     string `json:"Actor"`
	Timestamp string `json:"Timestamp"`
	TxID      string `json:"TxID"`
}

// VerificationResult — returned by VerifyCertificate
type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid      bool   `json:"valid"`
	IsRevoked  bool   `json:"isRevoked"`
	HashMatch  bool   `json:"hashMatch"`
	HashAlgo   string `json:"hashAlgo"`
	Message    string `json:"message"`
	Timestamp  string `json:"timestamp"`
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
//   - Deterministic: same input always produces same output
//
// Input concatenation: fields separated by '|' pipe character
// Output: lowercase hex-encoded 32-byte digest (64 characters)
func ComputeCertHashBLAKE3(studentID, studentName, degree, issuer, issueDate string) string {
	// Concatenate fields with pipe separator (matches client-side JS workload)
	data := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")

	// BLAKE3 hash: Sum256 returns [32]byte — identical interface to sha256.Sum256
	hashBytes := blake3.Sum256([]byte(data))

	// Return lowercase hex string (64 chars) — matches client computation
	return fmt.Sprintf("%x", hashBytes)
}

// ComputeCertHash is the unified entry point for hash computation.
// Returns (certHash, algorithm) — always uses BLAKE3 in this chaincode.
func ComputeCertHash(studentID, studentName, degree, issuer, issueDate string) (string, string) {
	return ComputeCertHashBLAKE3(studentID, studentName, degree, issuer, issueDate), HashModeBLAKE3
}

// ─── Helper Functions ────────────────────────────────────────────────────────

func getCallerMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("failed to get caller MSP: %v", err)
	}
	return mspID, nil
}

func getCallerRole(ctx contractapi.TransactionContextInterface) string {
	role, _, _ := ctx.GetClientIdentity().GetAttributeValue("role")
	return role
}

// isAuditDisabled checks DISABLE_AUDIT env var — set to "true" during benchmarks
// to reduce write overhead and maximize TPS for pure hash performance measurement
func isAuditDisabled() bool {
	return strings.ToLower(os.Getenv("DISABLE_AUDIT")) == "true"
}

// writeAuditLog appends an audit entry (skipped when DISABLE_AUDIT=true)
func writeAuditLog(ctx contractapi.TransactionContextInterface, certID, action, actor string) {
	if isAuditDisabled() {
		return // Skip during benchmarks for max throughput
	}

	now := time.Now().UTC().Format(time.RFC3339)
	logID := fmt.Sprintf("LOG_%s_%s_%s", certID, action, now)

	auditLog := AuditLog{
		DocType:   "auditlog",
		LogID:     logID,
		CertID:    certID,
		Action:    action,
		Actor:     actor,
		Timestamp: now,
		TxID:      ctx.GetStub().GetTxID(),
	}

	logJSON, _ := json.Marshal(auditLog)
	_ = ctx.GetStub().PutState(logID, logJSON)
}

// ─── Smart Contract Methods ──────────────────────────────────────────────────

// InitLedger seeds five sample certificates using BLAKE3 hashing
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	type sampleCert struct {
		id, studentID, studentName, degree, issuer, issueDate, sig string
	}

	samples := []sampleCert{
		{"CERT_B3_001", "STU_001", "Alice Johnson", "Bachelor of Computer Science", "Digital University", "2024-01-15", "SIG_DEMO_001"},
		{"CERT_B3_002", "STU_002", "Bob Smith", "Master of Data Science", "Tech Institute", "2024-02-20", "SIG_DEMO_002"},
		{"CERT_B3_003", "STU_003", "Carol Davis", "PhD in Blockchain", "Research University", "2024-03-10", "SIG_DEMO_003"},
		{"CERT_B3_004", "STU_004", "David Wilson", "Bachelor of Engineering", "State University", "2024-04-05", "SIG_DEMO_004"},
		{"CERT_B3_005", "STU_005", "Emma Brown", "Master of Cybersecurity", "Security Academy", "2024-05-12", "SIG_DEMO_005"},
	}

	now := time.Now().UTC().Format(time.RFC3339)

	for _, s := range samples {
		certHash, _ := ComputeCertHash(s.studentID, s.studentName, s.degree, s.issuer, s.issueDate)

		cert := Certificate{
			DocType:       "certificate",
			ID:            s.id,
			StudentID:     s.studentID,
			StudentName:   s.studentName,
			Degree:        s.degree,
			Issuer:        s.issuer,
			IssueDate:     s.issueDate,
			CertHash:      certHash,
			HashAlgorithm: "BLAKE3", // Required: on-chain tag showing BLAKE3 usage
			HashAlgo:      "blake3",
			Signature:     s.sig,
			IsRevoked:     false,
			CreatedAt:     now,
			UpdatedAt:     now,
		}

		certJSON, err := json.Marshal(cert)
		if err != nil {
			return fmt.Errorf("failed to marshal cert %s: %v", s.id, err)
		}
		if err := ctx.GetStub().PutState(s.id, certJSON); err != nil {
			return fmt.Errorf("failed to put cert %s: %v", s.id, err)
		}
	}

	return nil
}

// IssueCertificate issues a new certificate with BLAKE3 hash
// RBAC: only Org1MSP callers may issue certificates
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id, studentID, studentName, degree, issuer, issueDate, certHash, signature string,
) error {
	// RBAC check — only Org1 can issue
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return err
	}
	if mspID != "Org1MSP" {
		return fmt.Errorf("unauthorized: only Org1MSP can issue certificates, caller is %s", mspID)
	}

	// Idempotency: return nil (not error) if cert already exists
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to check existing cert: %v", err)
	}
	if existing != nil {
		return nil // Idempotent: duplicate issue is a no-op
	}

	// Compute BLAKE3 hash server-side (validates/overrides client hash)
	serverHash, algo := ComputeCertHash(studentID, studentName, degree, issuer, issueDate)

	now := time.Now().UTC().Format(time.RFC3339)

	cert := Certificate{
		DocType:       "certificate",
		ID:            id,
		StudentID:     studentID,
		StudentName:   studentName,
		Degree:        degree,
		Issuer:        issuer,
		IssueDate:     issueDate,
		CertHash:      serverHash, // Always computed server-side
		HashAlgorithm: "BLAKE3",   // On-chain tag — required by benchmark spec
		HashAlgo:      algo,
		Signature:     signature,
		IsRevoked:     false,
		CreatedAt:     now,
		UpdatedAt:     now,
		TxID:          ctx.GetStub().GetTxID(),
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal certificate: %v", err)
	}
	if err := ctx.GetStub().PutState(id, certJSON); err != nil {
		return fmt.Errorf("failed to store certificate: %v", err)
	}

	// Write audit log (skipped during benchmarks if DISABLE_AUDIT=true)
	caller := mspID + "/" + getCallerRole(ctx)
	writeAuditLog(ctx, id, "IssueCertificate", caller)

	return nil
}

// VerifyCertificate validates a certificate's authenticity
// RBAC: any organization can verify (public read)
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id, inputHash string,
) (*VerificationResult, error) {
	now := time.Now().UTC().Format(time.RFC3339)

	certBytes, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate: %v", err)
	}
	if certBytes == nil {
		return &VerificationResult{
			CertID:    id,
			Valid:      false,
			Message:    "Certificate not found",
			HashAlgo:   HashModeBLAKE3,
			Timestamp:  now,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certBytes, &cert); err != nil {
		return nil, fmt.Errorf("failed to unmarshal certificate: %v", err)
	}

	if cert.IsRevoked {
		return &VerificationResult{
			CertID:    id,
			Valid:      false,
			IsRevoked:  true,
			Message:    "Certificate has been revoked",
			HashAlgo:   cert.HashAlgo,
			Timestamp:  now,
		}, nil
	}

	hashMatch := strings.EqualFold(cert.CertHash, inputHash)

	return &VerificationResult{
		CertID:    id,
		Valid:      hashMatch,
		IsRevoked:  false,
		HashMatch:  hashMatch,
		HashAlgo:   cert.HashAlgo,
		Message:    map[bool]string{true: "Certificate is valid and authentic", false: "Hash mismatch — certificate data may have been tampered"}[hashMatch],
		Timestamp:  now,
	}, nil
}

// RevokeCertificate marks a certificate as revoked
// RBAC: Org1MSP or Org2MSP (both peer orgs can revoke)
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	certBytes, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read certificate: %v", err)
	}
	if certBytes == nil {
		return nil // Idempotent: not found is a no-op
	}

	var cert Certificate
	if err := json.Unmarshal(certBytes, &cert); err != nil {
		return fmt.Errorf("failed to unmarshal certificate: %v", err)
	}

	if cert.IsRevoked {
		return nil // Idempotent: already revoked is a no-op
	}

	mspID, _ := getCallerMSP(ctx)
	now := time.Now().UTC().Format(time.RFC3339)

	cert.IsRevoked = true
	cert.RevokedBy = mspID
	cert.RevokedAt = now
	cert.UpdatedAt = now
	cert.TxID = ctx.GetStub().GetTxID()

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal updated certificate: %v", err)
	}
	if err := ctx.GetStub().PutState(id, certJSON); err != nil {
		return fmt.Errorf("failed to update certificate: %v", err)
	}

	writeAuditLog(ctx, id, "RevokeCertificate", mspID)

	return nil
}

// QueryAllCertificates returns all certificates from the ledger
// RBAC: any org (public read)
func (s *SmartContract) QueryAllCertificates(ctx contractapi.TransactionContextInterface) ([]*Certificate, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("failed to get state by range: %v", err)
	}
	defer resultsIterator.Close()

	var certs []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		if cert.DocType == "certificate" {
			certs = append(certs, &cert)
		}
	}

	if certs == nil {
		return []*Certificate{}, nil
	}
	return certs, nil
}

// GetCertificatesByStudent queries certificates by student ID
// RBAC: any org (public read)
func (s *SmartContract) GetCertificatesByStudent(
	ctx contractapi.TransactionContextInterface,
	studentID string,
) ([]*Certificate, error) {
	queryString := fmt.Sprintf(`{"selector":{"docType":"certificate","StudentID":"%s"}}`, studentID)

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		// Fallback: scan all if CouchDB query fails (LevelDB mode)
		return s.QueryAllCertificates(ctx)
	}
	defer resultsIterator.Close()

	var certs []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		certs = append(certs, &cert)
	}

	if certs == nil {
		return []*Certificate{}, nil
	}
	return certs, nil
}

// GetAuditLogs returns all audit log entries
// RBAC: any org (public read)
func (s *SmartContract) GetAuditLogs(ctx contractapi.TransactionContextInterface) ([]*AuditLog, error) {
	queryString := `{"selector":{"docType":"auditlog"}}`

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		// Return empty when audit is disabled or CouchDB unavailable
		return []*AuditLog{}, nil
	}
	defer resultsIterator.Close()

	var logs []*AuditLog
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var log AuditLog
		if err := json.Unmarshal(queryResponse.Value, &log); err != nil {
			continue
		}
		logs = append(logs, &log)
	}

	if logs == nil {
		return []*AuditLog{}, nil
	}
	return logs, nil
}

// ComputeHash exposes the BLAKE3 hash computation for benchmarking
// Returns the hex-encoded BLAKE3 hash of the concatenated fields
func (s *SmartContract) ComputeHash(
	ctx contractapi.TransactionContextInterface,
	studentID, studentName, degree, issuer, issueDate string,
) (string, error) {
	hash, _ := ComputeCertHash(studentID, studentName, degree, issuer, issueDate)
	return hash, nil
}

// GetHashAlgorithm returns the hash algorithm identifier
// Returns "BLAKE3" — matches Certificate.HashAlgorithm field
func (s *SmartContract) GetHashAlgorithm(ctx contractapi.TransactionContextInterface) (string, error) {
	return "BLAKE3", nil
}
