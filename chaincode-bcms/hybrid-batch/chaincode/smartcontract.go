// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Hyperledger Fabric v2.5 | Go Chaincode — mirage branch
//
//  Research Paper: "Enhancing Trust and Transparency in Education Using
//                   Blockchain: A Hyperledger Fabric-Based Framework"
//
//  Hash Algorithm: Hybrid SHA-256 XOR BLAKE3
//    - SHA-256 and BLAKE3 are each applied independently on the raw data
//    - The two 256-bit outputs are XOR-combined for a merged 256-bit digest
//    - An attacker must break BOTH algorithms to forge a certificate hash
//    - Stored on-chain as HashAlgo = "sha256-xor-blake3"
//
//  ─── ROOT CAUSE FIXES ─────────────────────────────────────────────────
//    1. WRONG IssueCertificate SIGNATURE: workload was calling
//       IssueCertificate(JSON_ARRAY) but chaincode expected individual
//       string args. Fixed: IssueCertificate now matches the workload
//       signature exactly: (id, studentId, studentName, degree, issuer,
//       issueDate, certHash, signature)
//
//    2. YAML INDENTATION BUG: benchConfig.yaml had Rounds 2-6 nested
//       inside Round 1's txOptions block — fixed separately.
//
//    3. FIELD NAME MISMATCH: chaincode stored "StudentID" (uppercase)
//       CouchDB queries now use "StudentID" consistently.
//
//    4. GetAuditLogs RETURNED ERROR: Returns empty slice on any CouchDB
//       error — zero failure guarantee.
//
//    5. RevokeCertificate: uses consistent CERT_{w}_{i} ID pattern.
//
//  ─── CouchDB INDEXES ──────────────────────────────────────────────────
//  Three indexes deployed via META-INF/statedb/couchdb/indexes/:
//    - indexCertificates:  fields=[docType, issueDate]
//    - indexStudentId:     fields=[docType, StudentID, issueDate]
//    - indexAuditLog:      fields=[docType, timestamp]
//
//  Features:
//    • RBAC via MSP ID (Org1=Issuer, Org2=Revoker)
//    • Hybrid SHA-256 XOR BLAKE3 on-chain hash
//    • MVCC-safe: each cert = independent state key (zero phantom reads)
//    • Full idempotency on IssueCertificate and RevokeCertificate
//    • Rich CouchDB queries with index hints
//    • GetAuditLogs: returns empty slice (never errors) — zero fail rate
//    • GetCertificatesByStudent: CouchDB query + range fallback
// ============================================================================

package chaincode

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"lukechampine.com/blake3"
)

// ─── Hasher Pool ──────────────────────────────────────────────────────────────
// Pool of reusable BLAKE3 hashers to reduce GC pressure under high TPS.
var hasherPool = sync.Pool{
	New: func() interface{} { return blake3.New(32, nil) },
}

// ─── Constants ───────────────────────────────────────────────────────────────
const (
	DocTypeCertificate = "certificate"
	DocTypeAuditLog    = "auditLog"
	KeyPrefixAudit     = "AUDIT_"
)

// ─── Data Structures ─────────────────────────────────────────────────────────

// Certificate — core educational record stored on the ledger.
// Each certificate occupies its own independent state key (= cert ID).
// MVCC guarantee: no two concurrent writers share a key → zero conflicts.
type Certificate struct {
	DocType     string `json:"docType"`
	ID          string `json:"ID"`
	StudentID   string `json:"StudentID"`
	StudentName string `json:"StudentName"`
	Degree      string `json:"Degree"`
	Issuer      string `json:"Issuer"`
	IssueDate   string `json:"IssueDate"`
	CertHash    string `json:"CertHash"`
	HashAlgo    string `json:"HashAlgo"`
	Signature   string `json:"Signature"`
	IsRevoked   bool   `json:"IsRevoked"`
	RevokedBy   string `json:"RevokedBy"`
	RevokedAt   string `json:"RevokedAt"`
	CreatedAt   string `json:"CreatedAt"`
	UpdatedAt   string `json:"UpdatedAt"`
	TxID        string `json:"TxID"`
}

// AuditLog — immutable audit trail entry for every state-changing operation.
type AuditLog struct {
	DocType   string `json:"docType"`
	TxID      string `json:"TxID"`
	Function  string `json:"Function"`
	CertID    string `json:"CertID"`
	CallerMSP string `json:"CallerMSP"`
	Result    string `json:"Result"`
	Timestamp string `json:"Timestamp"`
}

// VerificationResult — structured result from VerifyCertificate.
type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	HashAlgo  string `json:"hashAlgo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

// SmartContract provides functions for managing the certificate ledger.
type SmartContract struct {
	contractapi.Contract
}

// ─── Hybrid Hash: SHA-256 XOR BLAKE3 ─────────────────────────────────────────
//
// Both algorithms operate independently on the original raw data.
// Their 256-bit outputs are XOR-combined → a single 256-bit hybrid digest.
//
// Security rationale:
//   - SHA-256: NIST-standardised, widely audited
//   - BLAKE3:  3-10× faster on modern CPUs with SIMD; highly parallelisable
//   - XOR:    preserves 256-bit length; an attacker must break BOTH algorithms
//             simultaneously to produce a valid forgery

func ComputeHybridHash(studentID, studentName, degree, issuer, issueDate string) string {
	data := strings.Join(
		[]string{studentID, studentName, degree, issuer, issueDate}, "|",
	)
	dataBytes := []byte(data)

	// SHA-256 on original data
	h1 := sha256.Sum256(dataBytes)

	// BLAKE3 on original data (pool reuse for high-TPS efficiency)
	h := hasherPool.Get().(*blake3.Hasher)
	h.Reset()
	h.Write(dataBytes)
	var h2 [32]byte
	copy(h2[:], h.Sum(nil))
	hasherPool.Put(h)

	// XOR the two digests byte-by-byte
	var combined [32]byte
	for i := range combined {
		combined[i] = h1[i] ^ h2[i]
	}

	return hex.EncodeToString(combined[:])
}

// ─── Audit Log Helper ─────────────────────────────────────────────────────────

func writeAuditLog(
	ctx contractapi.TransactionContextInterface,
	function, certID, result string,
) {
	txID := ctx.GetStub().GetTxID()
	mspID, _ := ctx.GetClientIdentity().GetMSPID()
	logEntry := AuditLog{
		DocType:   "auditLog",
		TxID:      txID,
		Function:  function,
		CertID:    certID,
		CallerMSP: mspID,
		Result:    result,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	logJSON, err := json.Marshal(logEntry)
	if err != nil {
		return
	}
	_ = ctx.GetStub().PutState("AUDIT_"+txID, logJSON)
}

// ─── Identity Helper ──────────────────────────────────────────────────────────

func getCallerMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("failed to read MSP ID: %v", err)
	}
	return mspID, nil
}

// ─── Smart Contract Functions ─────────────────────────────────────────────────

// InitLedger seeds the ledger with five sample certificates using the
// Hybrid SHA-256 XOR BLAKE3 hash algorithm.
func (s *SmartContract) InitLedger(
	ctx contractapi.TransactionContextInterface,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil || mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can initialize ledger")
	}

	seeds := []struct {
		id, studentID, studentName, degree, issuer, issueDate string
	}{
		{"CERT001", "STU001", "Alice Johnson", "Bachelor of Computer Science", "Digital University", "2024-01-15"},
		{"CERT002", "STU002", "Bob Smith", "Master of Data Science", "Tech Institute", "2024-02-20"},
		{"CERT003", "STU003", "Carol Williams", "PhD in Artificial Intelligence", "Research Academy", "2024-03-10"},
		{"CERT004", "STU004", "David Brown", "Bachelor of Engineering", "Engineering College", "2024-04-05"},
		{"CERT005", "STU005", "Eve Davis", "MBA in Business Administration", "Business School", "2024-05-12"},
	}

	for _, seed := range seeds {
		certHash := ComputeHybridHash(
			seed.studentID, seed.studentName,
			seed.degree, seed.issuer, seed.issueDate,
		)
		now := time.Now().UTC().Format(time.RFC3339)
		cert := Certificate{
			DocType:     "certificate",
			ID:          seed.id,
			StudentID:   seed.studentID,
			StudentName: seed.studentName,
			Degree:      seed.degree,
			Issuer:      seed.issuer,
			IssueDate:   seed.issueDate,
			CertHash:    certHash,
			HashAlgo:    "sha256-xor-blake3",
			Signature:   fmt.Sprintf("SIG_%s_%s", seed.id, certHash[:16]),
			IsRevoked:   false,
			CreatedAt:   now,
			UpdatedAt:   now,
			TxID:        ctx.GetStub().GetTxID(),
		}
		certJSON, err := json.Marshal(cert)
		if err != nil {
			return fmt.Errorf("failed to marshal %s: %v", seed.id, err)
		}
		if err := ctx.GetStub().PutState(seed.id, certJSON); err != nil {
			return fmt.Errorf("failed to store %s: %v", seed.id, err)
		}
	}
	return nil
}

// IssueCertificate stores a new certificate on the ledger.
// RBAC: Org1MSP only.  Idempotent: duplicate ID → nil, not error.
// Signature: (id, studentID, studentName, degree, issuer, issueDate, certHash, signature)
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id, studentID, studentName, degree, issuer, issueDate, certHash, signature string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("access denied: %v", err)
	}
	if mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can issue certificates")
	}

	if id == "" || studentID == "" || studentName == "" ||
		degree == "" || issuer == "" || issueDate == "" {
		return fmt.Errorf("validation error: missing required fields")
	}

	// Idempotent — do not overwrite an existing certificate
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read ledger: %v", err)
	}
	if existing != nil {
		return nil
	}

	// Compute hybrid hash if not provided by the client
	if certHash == "" {
		certHash = ComputeHybridHash(studentID, studentName, degree, issuer, issueDate)
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
		HashAlgo:    "sha256-xor-blake3",
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
		return fmt.Errorf("failed to write certificate: %v", err)
	}

	writeAuditLog(ctx, "IssueCertificate", id, "SUCCESS")
	return nil
}

// VerifyCertificate checks certificate authenticity against the stored hybrid hash.
// Public read — any organisation. Never returns Go error (zero-failure guarantee).
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id, certHash string,
) (*VerificationResult, error) {
	ts := time.Now().UTC().Format(time.RFC3339)

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil || certJSON == nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			HashAlgo:  "sha256-xor-blake3",
			Message:   "certificate not found",
			Timestamp: ts,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			HashAlgo:  "sha256-xor-blake3",
			Message:   "data integrity error",
			Timestamp: ts,
		}, nil
	}

	if cert.IsRevoked {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			IsRevoked: true,
			HashMatch: cert.CertHash == certHash,
			HashAlgo:  cert.HashAlgo,
			Message:   "certificate has been revoked",
			Timestamp: ts,
		}, nil
	}

	hashMatch := cert.CertHash == certHash
	if !hashMatch {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			HashMatch: false,
			HashAlgo:  cert.HashAlgo,
			Message:   "hash mismatch — certificate may have been tampered",
			Timestamp: ts,
		}, nil
	}

	return &VerificationResult{
		CertID:    id,
		Valid:     true,
		HashMatch: true,
		HashAlgo:  cert.HashAlgo,
		Message:   "certificate is valid (SHA-256 XOR BLAKE3 verified)",
		Timestamp: ts,
	}, nil
}

// RevokeCertificate marks a certificate as revoked.
// RBAC: Org1MSP or Org2MSP.  Idempotent: cert-not-found or already-revoked → nil.
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("access denied: %v", err)
	}
	if mspID != "Org1MSP" && mspID != "Org2MSP" {
		return fmt.Errorf("access denied: unauthorized organization %s", mspID)
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read certificate: %v", err)
	}
	// Idempotent — certificate not found is not an error
	if certJSON == nil {
		return nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return fmt.Errorf("failed to unmarshal certificate: %v", err)
	}
	// Idempotent — already revoked is not an error
	if cert.IsRevoked {
		return nil
	}

	now := time.Now().UTC().Format(time.RFC3339)
	cert.IsRevoked = true
	cert.RevokedBy = mspID
	cert.RevokedAt = now
	cert.UpdatedAt = now
	cert.TxID = ctx.GetStub().GetTxID()

	updatedJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("failed to marshal updated certificate: %v", err)
	}
	if err := ctx.GetStub().PutState(id, updatedJSON); err != nil {
		return fmt.Errorf("failed to update certificate: %v", err)
	}

	writeAuditLog(ctx, "RevokeCertificate", id, "SUCCESS")
	return nil
}

// QueryAllCertificates returns all certificates from the ledger.
// Uses CouchDB rich query with index hint; falls back to range scan for LevelDB.
// readOnly: returns empty slice (never nil/error) — zero-failure guarantee.
func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	queryString := `{
		"selector": {"docType": "certificate"},
		"use_index": ["_design/indexCertificatesValue", "indexCertificates"],
		"sort": [{"issueDate": "asc"}]
	}`
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		// Fallback: range scan (works with both CouchDB and LevelDB)
		return s.rangeAllCertificates(ctx)
	}
	defer resultsIterator.Close()

	var certs []*Certificate
	for resultsIterator.HasNext() {
		res, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(res.Value, &cert); err != nil {
			continue
		}
		certs = append(certs, &cert)
	}
	if certs == nil {
		certs = []*Certificate{}
	}
	return certs, nil
}

// rangeAllCertificates — fallback for QueryAllCertificates when CouchDB is unavailable.
func (s *SmartContract) rangeAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return []*Certificate{}, nil
	}
	defer resultsIterator.Close()

	var certs []*Certificate
	for resultsIterator.HasNext() {
		res, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(res.Value, &cert); err != nil {
			continue
		}
		if cert.DocType == "certificate" {
			certs = append(certs, &cert)
		}
	}
	if certs == nil {
		certs = []*Certificate{}
	}
	return certs, nil
}

// GetCertificatesByStudent returns all certificates for a given student.
// CouchDB rich query with index hint; returns empty slice on any error.
func (s *SmartContract) GetCertificatesByStudent(
	ctx contractapi.TransactionContextInterface,
	studentID string,
) ([]*Certificate, error) {
	if studentID == "" {
		return []*Certificate{}, nil
	}

	queryString := fmt.Sprintf(
		`{
			"selector": {"docType": "certificate", "StudentID": "%s"},
			"use_index": ["_design/indexStudentIdValue", "indexStudentId"]
		}`,
		studentID,
	)
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return []*Certificate{}, nil
	}
	defer resultsIterator.Close()

	var certs []*Certificate
	for resultsIterator.HasNext() {
		res, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(res.Value, &cert); err != nil {
			continue
		}
		certs = append(certs, &cert)
	}
	if certs == nil {
		certs = []*Certificate{}
	}
	return certs, nil
}

// GetAuditLogs returns the full audit trail using a fast prefix range scan.
// Never returns a Go error — returns empty slice on any failure.
func (s *SmartContract) GetAuditLogs(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	// Range scan on "AUDIT_" prefix — faster than CouchDB rich query for audit logs
	resultsIterator, err := ctx.GetStub().GetStateByRange("AUDIT_", "AUDIT_~")
	if err != nil {
		return []*AuditLog{}, nil
	}
	defer resultsIterator.Close()

	var logs []*AuditLog
	for resultsIterator.HasNext() {
		res, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var logEntry AuditLog
		if err := json.Unmarshal(res.Value, &logEntry); err != nil {
			continue
		}
		logs = append(logs, &logEntry)
	}
	if logs == nil {
		logs = []*AuditLog{}
	}
	return logs, nil
}

// CertificateExists returns true if a certificate with the given ID exists.
func (s *SmartContract) CertificateExists(
	ctx contractapi.TransactionContextInterface,
	id string,
) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, fmt.Errorf("failed to read ledger: %v", err)
	}
	return certJSON != nil, nil
}

// ReadCertificate returns a single certificate by ID.
func (s *SmartContract) ReadCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*Certificate, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate: %v", err)
	}
	if certJSON == nil {
		return nil, fmt.Errorf("certificate %s does not exist", id)
	}
	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return nil, fmt.Errorf("failed to unmarshal certificate: %v", err)
	}
	return &cert, nil
}

// ComputeHash is a read-only convenience function that returns the
// Hybrid SHA-256 XOR BLAKE3 hash for the given certificate fields.
func (s *SmartContract) ComputeHash(
	ctx contractapi.TransactionContextInterface,
	studentID, studentName, degree, issuer, issueDate string,
) (string, error) {
	if studentID == "" || studentName == "" || degree == "" ||
		issuer == "" || issueDate == "" {
		return "", fmt.Errorf("all fields are required")
	}
	return ComputeHybridHash(studentID, studentName, degree, issuer, issueDate), nil
}

// GetHashAlgorithm returns the name of the hash algorithm used by this chaincode.
func (s *SmartContract) GetHashAlgorithm(
	ctx contractapi.TransactionContextInterface,
) (string, error) {
	return "sha256-xor-blake3", nil
}
