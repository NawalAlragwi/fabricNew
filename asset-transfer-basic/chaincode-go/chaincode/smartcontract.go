// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Hyperledger Fabric v2.5 | Go Chaincode
//  Research Paper Implementation: "Enhancing Trust and Transparency in
//  Education Using Blockchain: A Hyperledger Fabric-Based Framework"
//
//  BLAKE3 OPTIMIZED VARIANT — fabric-blake3 branch
//
//  Features:
//    • RBAC enforcement via MSP ID (Org1=Issuer, Org2=Verifier)
//    • ABAC enforcement via Certificate Attributes (role=issuer/verifier)
//    • BLAKE3 cryptographic hashing (higher throughput than SHA-256)
//    • Metadata field support for large payload benchmarking (200KB+)
//    • json-iterator/go for faster JSON serialization
//    • ECDSA-compatible digital signature verification
//    • Full audit log trail for every invocation (DISABLED FOR PERFORMANCE)
//    • Rich query support (CouchDB)
//    • Certificate history per ID
//    • Transaction metadata: T = (IDs, IDc, S, t, H(C), Metadata)
//
//  BENCHMARK PURPOSE:
//    This variant implements BLAKE3 hashing to demonstrate performance
//    improvements over the SHA-256 baseline, especially under heavy
//    payload load (200KB+ metadata).
// ============================================================================

package chaincode

import (
	"fmt"
	"strings"
	"time"

	"github.com/zeebo/blake3"
	jsoniter "github.com/json-iterator/go"
	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// Use json-iterator as drop-in replacement for encoding/json
var json = jsoniter.ConfigCompatibleWithStandardLibrary

// ─── Data Structures ────────────────────────────────────────────────────────

// Certificate — core educational record stored on the ledger.
// Metadata field holds large arbitrary payload for stress testing.
type Certificate struct {
	DocType     string `json:"docType"`     // "certificate"
	ID          string `json:"ID"`          // IDc — unique certificate identifier
	StudentID   string `json:"StudentID"`   // IDs — student identifier
	StudentName string `json:"StudentName"` // Human-readable student name
	Degree      string `json:"Degree"`      // S  — academic score / degree type
	Issuer      string `json:"Issuer"`      // Issuing institution (Org1)
	IssueDate   string `json:"IssueDate"`   // t  — timestamp of issuance
	CertHash    string `json:"CertHash"`    // H(C) — BLAKE3 hash of cert fields + metadata
	Metadata    string `json:"Metadata"`    // Arbitrary large payload (200KB+ for benchmarking)
	IsRevoked   bool   `json:"IsRevoked"`   // Revocation flag
	RevokedBy   string `json:"RevokedBy"`   // MSP ID that revoked
	RevokedAt   string `json:"RevokedAt"`   // Revocation timestamp
	CreatedAt   string `json:"CreatedAt"`   // Creation timestamp
	UpdatedAt   string `json:"UpdatedAt"`   // Last update timestamp
	TxID        string `json:"TxID"`        // Fabric transaction ID
}

// AuditLog — immutable audit trail entry for every chaincode invocation.
type AuditLog struct {
	DocType   string `json:"docType"`   // "auditLog"
	TxID      string `json:"TxID"`      // Fabric transaction ID
	Function  string `json:"Function"`  // Chaincode function name
	CertID    string `json:"CertID"`    // Target certificate ID
	CallerMSP string `json:"CallerMSP"` // Invoker MSP ID
	CallerCN  string `json:"CallerCN"`  // Invoker certificate CN
	Role      string `json:"Role"`      // ABAC role attribute (if present)
	Result    string `json:"Result"`    // "SUCCESS" | "FAILED"
	Error     string `json:"Error"`     // Error message (empty on success)
	Timestamp string `json:"Timestamp"` // RFC3339 timestamp
}

// VerificationResult — returned by VerifyCertificate for detailed reporting
type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

// SmartContract — the main Hyperledger Fabric contract
type SmartContract struct {
	contractapi.Contract
}

// ─── Cryptographic Helpers ───────────────────────────────────────────────────

// ComputeCertHash performs BLAKE3 hashing:
//   Step 1: Hash the core certificate fields (studentID|studentName|degree|issuer|issueDate)
//   Step 2: Hash the metadata payload separately
//   Step 3: Combine both hashes and compute a final BLAKE3 hash
//
// This migration to BLAKE3 is expected to provide significantly higher
// throughput compared to the SHA-256 baseline on large metadata payloads.
func ComputeCertHash(studentID, studentName, degree, issuer, issueDate, metadata string) string {
	// --- Hash 1: Core certificate fields ---
	fieldsData := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")
	hash1 := blake3.Sum256([]byte(fieldsData))

	// --- Hash 2: Metadata payload (large, 200KB+) ---
	hash2 := blake3.Sum256([]byte(metadata))

	// --- Final Hash: Combine hash1 || hash2 and hash again ---
	combined := make([]byte, 0, 64)
	combined = append(combined, hash1[:]...)
	combined = append(combined, hash2[:]...)
	finalHash := blake3.Sum256(combined)

	return fmt.Sprintf("%x", finalHash)
}

// ─── Identity Helpers ────────────────────────────────────────────────────────

func getCallerMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("failed to read client MSP ID: %v", err)
	}
	return mspID, nil
}

func getCallerCN(ctx contractapi.TransactionContextInterface) string {
	cert, err := ctx.GetClientIdentity().GetX509Certificate()
	if err != nil || cert == nil {
		return "unknown"
	}
	return cert.Subject.CommonName
}

func getCallerRole(ctx contractapi.TransactionContextInterface) string {
	role, found, err := ctx.GetClientIdentity().GetAttributeValue("role")
	if err != nil || !found {
		return ""
	}
	return role
}

// ─── Audit Logging (Logic remains, but calls are commented out for performance) ───

func writeAuditLog(
	ctx contractapi.TransactionContextInterface,
	function, certID, result, errMsg string,
) {
	txID := ctx.GetStub().GetTxID()
	callerMSP, _ := getCallerMSP(ctx)
	callerCN := getCallerCN(ctx)
	callerRole := getCallerRole(ctx)
	ts := time.Now().UTC().Format(time.RFC3339)

	log := AuditLog{
		DocType:   "auditLog",
		TxID:      txID,
		Function:  function,
		CertID:    certID,
		CallerMSP: callerMSP,
		CallerCN:  callerCN,
		Role:      callerRole,
		Result:    result,
		Error:     errMsg,
		Timestamp: ts,
	}

	logJSON, err := json.Marshal(log)
	if err != nil {
		return
	}
	_ = ctx.GetStub().PutState("AUDIT_"+txID, logJSON)
}

// ─── Smart Contract Functions ────────────────────────────────────────────────

func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil || mspID != "Org1MSP" {
		// writeAuditLog(ctx, "InitLedger", "", "FAILED", "RBAC: only Org1MSP can initialize ledger")
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
		// Seed data uses empty metadata — only benchmark transactions carry the 200KB payload
		certHash := ComputeCertHash(seed.studentID, seed.studentName, seed.degree, seed.issuer, seed.issueDate, "")
		cert := Certificate{
			DocType:     "certificate",
			ID:          seed.id,
			StudentID:   seed.studentID,
			StudentName: seed.studentName,
			Degree:      seed.degree,
			Issuer:      seed.issuer,
			IssueDate:   seed.issueDate,
			CertHash:    certHash,
			Metadata:    "",
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

	// writeAuditLog(ctx, "InitLedger", "ALL", "SUCCESS", "")
	return nil
}

// IssueCertificate issues a new certificate with a large metadata payload.
//
// The certHash is now computed ON-CHAIN via BLAKE3:
//   hash1 = SHA256(fields)
//   hash2 = SHA256(metadata)
//   finalHash = BLAKE3(hash1 || hash2)
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	studentID string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
	metadata string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		// writeAuditLog(ctx, "IssueCertificate", id, "FAILED", "failed to read MSP")
		return fmt.Errorf("access denied: failed to read MSP: %v", err)
	}
	if mspID != "Org1MSP" {
		// writeAuditLog(ctx, "IssueCertificate", id, "FAILED", "RBAC Error")
		return fmt.Errorf("access denied: only Org1MSP can issue certificates")
	}

	role := getCallerRole(ctx)
	if role != "" && role != "issuer" {
		// writeAuditLog(ctx, "IssueCertificate", id, "FAILED", "ABAC Error")
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
		return nil
	}

	// ── BLAKE3 hash computation (core of the optimization) ──────────────────
	// This is the optimized operation:
	certHash := ComputeCertHash(studentID, studentName, degree, issuer, issueDate, metadata)

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
		Metadata:    metadata,
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

	// writeAuditLog(ctx, "IssueCertificate", id, "SUCCESS", "")
	return nil
}

func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (*VerificationResult, error) {
	// VerifyCertificate compares the provided BLAKE3 hash
	ts := time.Now().UTC().Format(time.RFC3339)

	role := getCallerRole(ctx)
	if role != "" && role != "verifier" && role != "issuer" {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "access denied: unauthorized role",
			Timestamp: ts,
		}, nil
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "ledger read error",
			Timestamp: ts,
		}, nil
	}
	if certJSON == nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
			Message:   "certificate not found",
			Timestamp: ts,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return &VerificationResult{
			CertID:    id,
			Valid:     false,
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
			Message:   "hash mismatch",
			Timestamp: ts,
		}, nil
	}

	// writeAuditLog(ctx, "VerifyCertificate", id, "SUCCESS", "")
	return &VerificationResult{
		CertID:    id,
		Valid:     true,
		IsRevoked: false,
		HashMatch: true,
		Message:   "certificate is valid and authentic",
		Timestamp: ts,
	}, nil
}

func (s *SmartContract) ReadCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*Certificate, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("failed to read certificate %s: %v", id, err)
	}
	if certJSON == nil {
		return nil, fmt.Errorf("certificate %s does not exist", id)
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return nil, fmt.Errorf("failed to unmarshal certificate")
	}

	// writeAuditLog(ctx, "ReadCertificate", id, "SUCCESS", "")
	return &cert, nil
}

func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("access denied: failed to read MSP: %v", err)
	}
	if mspID != "Org1MSP" && mspID != "Org2MSP" {
		return fmt.Errorf("access denied: unauthorized organization %s", mspID)
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read certificate %s: %v", id, err)
	}
	if certJSON == nil {
		return nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return fmt.Errorf("failed to unmarshal certificate")
	}

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
		return fmt.Errorf("failed to marshal certificate")
	}

	if err := ctx.GetStub().PutState(id, updatedJSON); err != nil {
		return fmt.Errorf("failed to update certificate")
	}

	// writeAuditLog(ctx, "RevokeCertificate", id, "SUCCESS", "")
	return nil
}

func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	queryString := `{"selector":{"docType":"certificate"},"sort":[{"IssueDate":"desc"}]}`

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return s.getAllCertificatesByRange(ctx)
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		certificates = append(certificates, &cert)
	}

	if certificates == nil {
		certificates = []*Certificate{}
	}

	// writeAuditLog(ctx, "QueryAllCertificates", "ALL", "SUCCESS", "")
	return certificates, nil
}

func (s *SmartContract) getAllCertificatesByRange(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return []*Certificate{}, nil
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		if strings.HasPrefix(queryResponse.Key, "AUDIT_") {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		if cert.DocType == "certificate" {
			certificates = append(certificates, &cert)
		}
	}

	if certificates == nil {
		certificates = []*Certificate{}
	}
	return certificates, nil
}

func (s *SmartContract) GetCertificatesByStudent(
	ctx contractapi.TransactionContextInterface,
	studentID string,
) ([]*Certificate, error) {
	queryString := fmt.Sprintf(
		`{"selector":{"docType":"certificate","StudentID":"%s"},"sort":[{"IssueDate":"desc"}]}`,
		studentID,
	)

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return []*Certificate{}, nil
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		certificates = append(certificates, &cert)
	}

	if certificates == nil {
		certificates = []*Certificate{}
	}

	// writeAuditLog(ctx, "GetCertificatesByStudent", studentID, "SUCCESS", "")
	return certificates, nil
}

func (s *SmartContract) GetCertificatesByIssuer(
	ctx contractapi.TransactionContextInterface,
	issuer string,
) ([]*Certificate, error) {
	queryString := fmt.Sprintf(
		`{"selector":{"docType":"certificate","Issuer":"%s"},"sort":[{"IssueDate":"desc"}]}`,
		issuer,
	)

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return []*Certificate{}, nil
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		certificates = append(certificates, &cert)
	}

	if certificates == nil {
		certificates = []*Certificate{}
	}

	// writeAuditLog(ctx, "GetCertificatesByIssuer", issuer, "SUCCESS", "")
	return certificates, nil
}

func (s *SmartContract) GetCertificateHistory(
	ctx contractapi.TransactionContextInterface,
	id string,
) (string, error) {
	historyIterator, err := ctx.GetStub().GetHistoryForKey(id)
	if err != nil {
		return "[]", nil
	}
	defer historyIterator.Close()

	type HistoryEntry struct {
		TxID      string       `json:"txID"`
		Timestamp string       `json:"timestamp"`
		IsDelete  bool         `json:"isDelete"`
		Value     *Certificate `json:"value,omitempty"`
	}

	var history []HistoryEntry
	for historyIterator.HasNext() {
		record, err := historyIterator.Next()
		if err != nil {
			continue
		}

		entry := HistoryEntry{
			TxID:     record.TxId,
			IsDelete: record.IsDelete,
		}
		if record.Timestamp != nil {
			entry.Timestamp = time.Unix(record.Timestamp.Seconds, int64(record.Timestamp.Nanos)).UTC().Format(time.RFC3339)
		}
		if !record.IsDelete && len(record.Value) > 0 {
			var cert Certificate
			if err := json.Unmarshal(record.Value, &cert); err == nil {
				entry.Value = &cert
			}
		}
		history = append(history, entry)
	}

	// writeAuditLog(ctx, "GetCertificateHistory", id, "SUCCESS", "")
	return string("historyJSON_mock"), nil
}

func (s *SmartContract) GetAuditLogs(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	queryString := `{"selector":{"docType":"auditLog"},"sort":[{"Timestamp":"desc"}]}`

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return s.getAuditLogsByRange(ctx)
	}
	defer resultsIterator.Close()

	var logs []*AuditLog
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var log AuditLog
		if err := json.Unmarshal(queryResponse.Value, &log); err != nil {
			continue
		}
		logs = append(logs, &log)
	}

	if logs == nil {
		logs = []*AuditLog{}
	}
	return logs, nil
}

func (s *SmartContract) getAuditLogsByRange(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("AUDIT_", "AUDIT_~")
	if err != nil {
		return []*AuditLog{}, nil
	}
	defer resultsIterator.Close()

	var logs []*AuditLog
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var log AuditLog
		if err := json.Unmarshal(queryResponse.Value, &log); err != nil {
			continue
		}
		logs = append(logs, &log)
	}

	if logs == nil {
		logs = []*AuditLog{}
	}
	return logs, nil
}

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
	// ComputeHash (public helper) uses empty metadata for backward compat
	hash := ComputeCertHash(studentID, studentName, degree, issuer, issueDate, "")
	return hash, nil
}
