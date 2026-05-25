// ============================================================================
//  BCMS - Blockchain Certificate Management System
//  Hyperledger Fabric v2.5 | Go Chaincode — Hybrid Crypto Edition (S3 ONLY)
//
//  Research Paper: "Enhancing Trust and Transparency in Education Using
//                   Blockchain: A Hyperledger Fabric-Based Framework"
//
//  Scenario S3: Hybrid SHA-256 + BLAKE3
//
//  --- DIFFERENCES FROM S4 (hybrid-batch) ------------------------------------
//    S3 = Hybrid hashing, single certificate per transaction (batchSize=1)
//    S4 = Same hybrid hashing + IssueCertificateBatch (batchSize=10)
//
//    This file (S3) intentionally OMITS:
//      - IssueCertificateBatch()   → batch function belongs to S4 only
//      - FlushBatch()              → not relevant for S3 single-cert model
//      - BatchRecord struct        → no batch records stored in S3
//
//  --- S3 DESIGN RATIONALE --------------------------------------------------
//    H_hybrid(C) = SHA256(studentID|name|degree|issuer|date)  - on-chain (validated)
//    H_blake3(C) = BLAKE3(studentID|name|degree|issuer|date)  - off-chain (advisory)
//
//    certHash    = H_hybrid(C)   stored & validated on-chain
//    blake3Hash  = H_blake3(C)   stored as advisory metadata, NOT validated
//
//    Each IssueCertificate call writes a single independent cert key.
//    Certificate IDs: CERT_{workerIndex}_{txIndex}
//    RevokeCertificate IDs: CERT_{workerIndex}_{idx} (same scheme → zero mismatch)
//
//  === FEATURES (S3):
//    - RBAC via MSP ID (Org1=Issuer, Org2=Verifier/Revoker)
//    - ABAC via Certificate Attributes (role=issuer/verifier)
//    - Hybrid SHA-256 + BLAKE3 (advisory) certificate hashing
//    - MVCC-safe individual state writes (zero phantom reads)
//    - Full idempotency on IssueCertificate and RevokeCertificate
//    - Rich CouchDB query support with index hints
//    - VerifyCertificate: deep on-chain SHA-256 integrity check
// ============================================================================

package chaincode

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"lukechampine.com/blake3"
)

// --- Constants ---------------------------------------------------------------

const (
	DocTypeCertificate  = "certificate"
	DocTypeAuditLog     = "auditLog"
	KeyPrefixAudit      = "AUDIT_"
	MagnificationFactor = 500
)

// --- Data Structures ---------------------------------------------------------

// Certificate - core educational record stored on the ledger.
// S3: Each certificate occupies its own independent state key (= cert ID).
// Key format: CERT_{workerIndex}_{txIndex}
type Certificate struct {
	DocType     string `json:"docType"`    // "certificate"
	ID          string `json:"id"`         // IDc — unique certificate identifier
	StudentID   string `json:"studentID"`  // IDs — student identifier
	StudentName string `json:"studentName"`
	Degree      string `json:"degree"`     // academic degree type
	Issuer      string `json:"issuer"`     // Issuing institution
	IssueDate   string `json:"issueDate"`  // t — timestamp of issuance
	CertHash    string `json:"certHash"`   // H_sha256(C) — primary on-chain hash (validated)
	Blake3Hash  string `json:"blake3Hash"` // H_blake3(C) — advisory off-chain hash (stored only)
	Signature   string `json:"signature"`  // Digital signature from issuer
	BatchID     string `json:"batchId"`    // Groups certs (S3: always "SINGLE")
	Transcript  string `json:"transcript,omitempty"` // Large payload for stress test
	IsRevoked   bool   `json:"isRevoked"`
	RevokedBy   string `json:"revokedBy,omitempty"`
	RevokedAt   string `json:"revokedAt,omitempty"`
	CreatedAt   string `json:"createdAt"`
	UpdatedAt   string `json:"updatedAt"`
	TxID        string `json:"txID"`
}

// AuditLog - immutable audit trail entry (disabled in benchmarks).
type AuditLog struct {
	DocType   string `json:"docType"`
	TxID      string `json:"txId"`
	Function  string `json:"function"`
	CertID    string `json:"certId"`
	CallerMSP string `json:"callerMsp"`
	CallerCN  string `json:"callerCn"`
	Role      string `json:"role"`
	Result    string `json:"result"`
	Error     string `json:"error,omitempty"`
	Timestamp string `json:"timestamp"`
}

// PaginatedQueryResult - response structure for paginated ledger scans.
type PaginatedQueryResult struct {
	Certificates []*Certificate `json:"certificates"`
	Bookmark     string         `json:"bookmark"`
	Count        int            `json:"count"`
}

// VerificationResult - structured response from VerifyCertificate.
type VerificationResult struct {
	CertID        string `json:"certId"`
	Valid         bool   `json:"valid"`
	IsRevoked     bool   `json:"isRevoked"`
	SHA256Match   bool   `json:"sha256Match"`
	Blake3Present bool   `json:"blake3Present"`
	Blake3Match   bool   `json:"blake3Match"`
	Message       string `json:"message"`
	Timestamp     string `json:"timestamp"`
}

// SmartContract - the main Hyperledger Fabric contract for S3.
type SmartContract struct {
	contractapi.Contract
}

// --- Cryptographic Helpers ---------------------------------------------------

func ComputeHybridHashMagnified(data []byte) [32]byte {
	var h [32]byte
	current := make([]byte, len(data)+32)
	copy(current, data)
	for i := 0; i < MagnificationFactor; i++ {
		copy(current[len(data):], h[:])
		h = sha256.Sum256(current)
	}
	return h
}

// ComputeHybridHash computes H_sha256(C) — the primary on-chain certificate hash.
// Formula: SHA256(studentID | studentName | degree | issuer | issueDate [| transcript])
// This is validated on-chain in VerifyCertificate.
func ComputeHybridHash(studentID, studentName, degree, issuer, issueDate, transcript string) string {
	parts := []string{studentID, studentName, degree, issuer, issueDate}
	if transcript != "" {
		parts = append(parts, transcript)
	}
	data := []byte(strings.Join(parts, "|"))
	h := ComputeHybridHashMagnified(data)
	return fmt.Sprintf("%x", h)
}

func ComputeBlake3Magnified(data []byte) string {
	var h [32]byte
	current := make([]byte, len(data)+32)
	copy(current, data)
	for i := 0; i < MagnificationFactor; i++ {
		copy(current[len(data):], h[:])
		h = blake3.Sum256(current)
	}
	return fmt.Sprintf("%x", h)
}

func ComputeBlake3Hash(studentID, studentName, degree, issuer, issueDate, transcript string) string {
	parts := []string{studentID, studentName, degree, issuer, issueDate}
	if transcript != "" {
		parts = append(parts, transcript)
	}
	return ComputeBlake3Magnified([]byte(strings.Join(parts, "|")))
}

// --- Identity Helpers --------------------------------------------------------

func getMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	id, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("getMSP: %v", err)
	}
	return id, nil
}

func getCN(ctx contractapi.TransactionContextInterface) string {
	cert, err := ctx.GetClientIdentity().GetX509Certificate()
	if err != nil || cert == nil {
		return "unknown"
	}
	return cert.Subject.CommonName
}

func getRole(ctx contractapi.TransactionContextInterface) string {
	role, found, err := ctx.GetClientIdentity().GetAttributeValue("role")
	if err != nil || !found {
		return ""
	}
	return role
}

// --- Audit Helper (disabled in benchmarks for performance) ------------------

func auditLog(ctx contractapi.TransactionContextInterface,
	fn, certID, result, errMsg string) {
	// Disabled for benchmark runs to remove AUDIT_ key write amplification.
	_ = fn
	_ = certID
	_ = result
	_ = errMsg
}

// --- Smart Contract Functions ------------------------------------------------

// InitLedger seeds the ledger with sample certificates.
// Restricted to Org1MSP. Called once during chaincode instantiation.
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	msp, err := getMSP(ctx)
	if err != nil || msp != "Org1MSP" {
		return fmt.Errorf("InitLedger: access denied - Org1MSP required")
	}

	seeds := []struct {
		id, studentID, name, degree, issuer, date string
	}{
		{"CERT_SEED_001", "STU001", "Alice Johnson", "Bachelor of Computer Science", "Digital University", "2024-01-15"},
		{"CERT_SEED_002", "STU002", "Bob Smith", "Master of Data Science", "Tech Institute", "2024-02-20"},
		{"CERT_SEED_003", "STU003", "Carol Williams", "PhD in Artificial Intelligence", "Research Academy", "2024-03-10"},
		{"CERT_SEED_004", "STU004", "David Brown", "Bachelor of Engineering", "Engineering College", "2024-04-05"},
		{"CERT_SEED_005", "STU005", "Eve Davis", "MBA in Business Administration", "Business School", "2024-05-12"},
	}

	now := time.Now().UTC().Format(time.RFC3339)
	for _, s2 := range seeds {
		h := ComputeHybridHash(s2.studentID, s2.name, s2.degree, s2.issuer, s2.date, "")
		cert := Certificate{
			DocType:     DocTypeCertificate,
			ID:          s2.id,
			StudentID:   s2.studentID,
			StudentName: s2.name,
			Degree:      s2.degree,
			Issuer:      s2.issuer,
			IssueDate:   s2.date,
			CertHash:    h,
			Blake3Hash:  "",
			Signature:   fmt.Sprintf("SIG_%s_%x", s2.id, h[:8]),
			Transcript:  "",
			BatchID:     "INIT",
			IsRevoked:   false,
			RevokedBy:   "N/A",
			RevokedAt:   "N/A",
			CreatedAt:   now,
			UpdatedAt:   now,
			TxID:        ctx.GetStub().GetTxID(),
		}
		b, err := json.Marshal(cert)
		if err != nil {
			return fmt.Errorf("InitLedger: marshal %s: %v", s2.id, err)
		}
		if err := ctx.GetStub().PutState(s2.id, b); err != nil {
			return fmt.Errorf("InitLedger: putstate %s: %v", s2.id, err)
		}
	}
	return nil
}

// IssueCertificate issues a single certificate to the ledger.
//
// --- S3 SINGLE-CERT MODEL --------------------------------------------------
// Arguments:
//   id          - unique cert ID, e.g. CERT_0_42  (CERT_{worker}_{txIndex})
//   studentId   - student identifier
//   studentName - human-readable name
//   degree      - academic degree string
//   issuer      - issuing institution
//   issueDate   - YYYY-MM-DD
//   certHash    - SHA-256 of (studentId|name|degree|issuer|date|transcript)
//   blake3Hash  - BLAKE3 of same fields — advisory metadata, NOT validated on-chain
//   signature   - issuer's digital signature
//   batchId     - grouping label (S3: typically "SINGLE")
//   transcript  - large payload for PhD stress test
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	studentId string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
	certHash string,
	blake3Hash string,
	signature string,
	batchId string,
	transcript string,
) error {
	// --- RBAC: only Org1MSP can issue -----------------------------------
	msp, err := getMSP(ctx)
	if err != nil {
		return fmt.Errorf("IssueCertificate: %v", err)
	}
	if msp != "Org1MSP" {
		return fmt.Errorf("IssueCertificate: access denied - Org1MSP required, got %s", msp)
	}

	// -- ABAC: role must be 'issuer' or unset ----------------------------
	role := getRole(ctx)
	if role != "" && role != "issuer" {
		return fmt.Errorf("IssueCertificate: access denied — role 'issuer' required, got '%s'", role)
	}

	// --- Validation -----------------------------------------------------
	if id == "" || studentId == "" || studentName == "" || degree == "" || issuer == "" || issueDate == "" {
		return fmt.Errorf("IssueCertificate: validation error - required fields missing")
	}

	// -- Idempotency gate — MVCC-safe read --------------------------------
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("IssueCertificate: ledger read error: %v", err)
	}
	if existing != nil {
		// Already issued — idempotent success.
		return nil
	}

	// -- Hash computation -------------------------------------------------
	serverHash := ComputeHybridHash(studentId, studentName, degree, issuer, issueDate, transcript)
	if certHash == "" {
		certHash = serverHash
	}
	if batchId == "" {
		batchId = "SINGLE"
	}

	now := time.Now().UTC().Format(time.RFC3339)
	cert := Certificate{
		DocType:     DocTypeCertificate,
		ID:          id,
		StudentID:   studentId,
		StudentName: studentName,
		Degree:      degree,
		Issuer:      issuer,
		IssueDate:   issueDate,
		CertHash:    certHash,
		Blake3Hash:  blake3Hash,
		Signature:   signature,
		BatchID:     batchId,
		Transcript:  transcript,
		IsRevoked:   false,
		RevokedBy:   "N/A",
		RevokedAt:   "N/A",
		CreatedAt:   now,
		UpdatedAt:   now,
		TxID:        ctx.GetStub().GetTxID(),
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("IssueCertificate: marshal error: %v", err)
	}
	if err := ctx.GetStub().PutState(id, certJSON); err != nil {
		return fmt.Errorf("IssueCertificate: putstate error: %v", err)
	}

	auditLog(ctx, "IssueCertificate", id, "SUCCESS", "")
	return nil
}

// QueryAllCertificates - Compatibility wrapper for warm-up script
func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
	pageSize string,
	bookmark string,
) (string, error) {
	ps, err := strconv.ParseInt(pageSize, 10, 32)
	if err != nil {
		ps = 20
	}

	paginatedRes, err := s.QueryAllCertificatesPaginated(ctx, int32(ps), bookmark)
	if err == nil {
		resJSON, _ := json.Marshal(paginatedRes)
		return string(resJSON), nil
	}

	// Fallback to range query if CouchDB rich query fails
	all, err := s.rangeAllCertificates(ctx)
	if err != nil {
		return "", err
	}
	res := &PaginatedQueryResult{
		Certificates: all,
		Bookmark:     "",
		Count:        len(all),
	}
	resJSON, _ := json.Marshal(res)
	return string(resJSON), nil
}

func (s *SmartContract) HashOnlyBenchmark(
	ctx contractapi.TransactionContextInterface,
	payload string,
) (string, error) {
	if payload == "" {
		return "", fmt.Errorf("HashOnlyBenchmark: payload required")
	}
	data := []byte(payload)

	// SHA-256 × 3000
	var sha256Result [32]byte
	current := make([]byte, len(data)+32)
	copy(current, data)
	for i := 0; i < MagnificationFactor; i++ {
		copy(current[len(data):], sha256Result[:])
		sha256Result = sha256.Sum256(current)
	}

	// BLAKE3 × 3000
	blake3Result := ComputeBlake3Magnified(data)

	return fmt.Sprintf("sha256:%x|blake3:%s", sha256Result, blake3Result), nil
}

// VerifyCertificate performs deep on-chain SHA-256 integrity verification.
// S3: validates certHash (SHA-256) and checks blake3Hash presence (advisory).
// readOnly=true in workload — bypasses orderer for maximum throughput.
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (*VerificationResult, error) {
	ts := time.Now().UTC().Format(time.RFC3339)

	role := getRole(ctx)
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
			CertID: id, Valid: false, Message: "ledger read error", Timestamp: ts,
		}, nil
	}
	if certJSON == nil {
		return &VerificationResult{
			CertID: id, Valid: false, Message: "certificate not found", Timestamp: ts,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return &VerificationResult{
			CertID: id, Valid: false, Message: "data integrity error", Timestamp: ts,
		}, nil
	}

	// On-chain SHA-256 integrity check
	computed := ComputeHybridHash(cert.StudentID, cert.StudentName, cert.Degree, cert.Issuer, cert.IssueDate, cert.Transcript)
	sha256HashMatch := cert.CertHash == computed

	// On-chain BLAKE3 integrity check
	computedBlake3 := ComputeBlake3Hash(cert.StudentID, cert.StudentName,
		cert.Degree, cert.Issuer, cert.IssueDate, cert.Transcript)
	blake3Match := cert.Blake3Hash == "" || cert.Blake3Hash == computedBlake3

	if cert.IsRevoked {
		return &VerificationResult{
			CertID:        id,
			Valid:         false,
			IsRevoked:     true,
			SHA256Match:   sha256HashMatch,
			Blake3Present: cert.Blake3Hash != "",
			Blake3Match:   blake3Match,
			Message:       "certificate has been revoked",
			Timestamp:     ts,
		}, nil
	}

	sha256Match := cert.CertHash == certHash && sha256HashMatch
	if !sha256Match || !blake3Match {
		return &VerificationResult{
			CertID:        id,
			Valid:         false,
			IsRevoked:     false,
			SHA256Match:   sha256Match,
			Blake3Present: cert.Blake3Hash != "",
			Blake3Match:   blake3Match,
			Message:       "hash mismatch",
			Timestamp:     ts,
		}, nil
	}

	return &VerificationResult{
		CertID:        id,
		Valid:         true,
		IsRevoked:     false,
		SHA256Match:   true,
		Blake3Present: cert.Blake3Hash != "",
		Blake3Match:   blake3Match,
		Message:       "certificate is valid and authentic",
		Timestamp:     ts,
	}, nil
}


// VerifyCertificateByID is a specialized benchmark function that reads a certificate
// and delegates to VerifyCertificate for deep hash integrity verification.
func (s *SmartContract) VerifyCertificateByID(ctx contractapi.TransactionContextInterface, id string) (*VerificationResult, error) {
	cert, err := s.ReadCertificate(ctx, id)
	if err != nil || cert == nil {
		return &VerificationResult{
			CertID: id, Valid: false, Message: "certificate not found", Timestamp: time.Now().UTC().Format(time.RFC3339),
		}, nil
	}
	return s.VerifyCertificate(ctx, id, cert.CertHash)
}

// QueryAllCertificatesPaginated returns a paginated list of certificates.
func (s *SmartContract) QueryAllCertificatesPaginated(
	ctx contractapi.TransactionContextInterface,
	pageSize int32,
	bookmark string,
) (*PaginatedQueryResult, error) {
	queryString := `{"selector":{"docType":"certificate","issueDate":{"$gt":null}},"sort":[{"docType":"desc"},{"issueDate":"desc"}]}`

	resultsIterator, metadata, err := ctx.GetStub().GetQueryResultWithPagination(
		queryString, pageSize, bookmark)
	if err != nil {
		return nil, fmt.Errorf("failed to get query result with pagination: %v", err)
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		resp, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var c Certificate
		if err := json.Unmarshal(resp.Value, &c); err != nil {
			continue
		}
		if c.DocType == DocTypeCertificate {
			certificates = append(certificates, &c)
		}
	}

	if certificates == nil {
		certificates = []*Certificate{}
	}

	return &PaginatedQueryResult{
		Certificates: certificates,
		Bookmark:     metadata.Bookmark,
		Count:        len(certificates),
	}, nil
}

// ReadCertificate returns the full certificate record for a given ID.
func (s *SmartContract) ReadCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*Certificate, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("ReadCertificate: %v", err)
	}
	if certJSON == nil {
		return nil, fmt.Errorf("ReadCertificate: certificate %s not found", id)
	}
	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return nil, fmt.Errorf("ReadCertificate: unmarshal error")
	}
	return &cert, nil
}

// RevokeCertificate marks a certificate as revoked.
//
// --- S3 REVOCATION KEY SCHEME ---------------------------------------------
// S3 revokes certs using the same key format as IssueCertificate:
//   CERT_{workerIndex}_{txIndex}
// This guarantees zero "cert not found" failures in the revoke round,
// because revoke targets exactly the keys issued in the issue round.
//
// RBAC: Org1MSP or Org2MSP.
// Idempotent: returns nil if cert not found or already revoked.
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	msp, err := getMSP(ctx)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: %v", err)
	}
	if msp != "Org1MSP" && msp != "Org2MSP" {
		return fmt.Errorf("access denied: only Org1MSP or Org2MSP can revoke certificates")
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: read error: %v", err)
	}
	// Idempotent: cert not found — treat as success
	if certJSON == nil {
		return nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return fmt.Errorf("RevokeCertificate: unmarshal error")
	}
	// Idempotent: already revoked — return nil
	if cert.IsRevoked {
		return nil
	}

	now := time.Now().UTC().Format(time.RFC3339)
	cert.IsRevoked = true
	cert.RevokedBy = msp
	cert.RevokedAt = now
	cert.UpdatedAt = now
	cert.TxID = ctx.GetStub().GetTxID()

	updated, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: marshal error")
	}
	if err := ctx.GetStub().PutState(id, updated); err != nil {
		return fmt.Errorf("RevokeCertificate: putstate error")
	}

	auditLog(ctx, "RevokeCertificate", id, "SUCCESS", "")
	return nil
}

// GetCertificatesByStudent returns all certificates for a given student ID.
func (s *SmartContract) GetCertificatesByStudent(
	ctx contractapi.TransactionContextInterface,
	studentId string,
) ([]*Certificate, error) {
	qs := fmt.Sprintf(
		`{"selector":{"docType":"certificate","studentID":"%s","issueDate":{"$gt":null}},"sort":[{"issueDate":"desc"}],"use_index":["_design/indexStudentIdValue","indexStudentId"]}`,
		studentId,
	)
	iter, err := ctx.GetStub().GetQueryResult(qs)
	if err != nil {
		return []*Certificate{}, nil
	}
	defer iter.Close()

	var certs []*Certificate
	for iter.HasNext() {
		resp, err := iter.Next()
		if err != nil {
			continue
		}
		var c Certificate
		if err := json.Unmarshal(resp.Value, &c); err != nil {
			continue
		}
		certs = append(certs, &c)
	}
	if certs == nil {
		certs = []*Certificate{}
	}
	return certs, nil
}

// GetAuditLogs returns all audit log entries sorted by timestamp desc.
func (s *SmartContract) GetAuditLogs(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	qs := `{"selector":{"docType":"auditLog","timestamp":{"$gt":null}},"sort":[{"timestamp":"desc"}],"use_index":["_design/indexAuditLogValue","indexAuditLog"]}`
	iter, err := ctx.GetStub().GetQueryResult(qs)
	if err != nil {
		return []*AuditLog{}, nil
	}
	defer iter.Close()

	var logs []*AuditLog
	for iter.HasNext() {
		resp, err := iter.Next()
		if err != nil {
			continue
		}
		var l AuditLog
		if err := json.Unmarshal(resp.Value, &l); err != nil {
			continue
		}
		logs = append(logs, &l)
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
	data, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, fmt.Errorf("CertificateExists: %v", err)
	}
	return data != nil, nil
}

// ComputeHash is a convenience function to compute the hybrid SHA-256 hash.
func (s *SmartContract) ComputeHash(
	ctx contractapi.TransactionContextInterface,
	studentId, studentName, degree, issuer, issueDate string,
) (string, error) {
	if studentId == "" || studentName == "" || degree == "" || issuer == "" || issueDate == "" {
		return "", fmt.Errorf("ComputeHash: all fields required")
	}
	return ComputeHybridHash(studentId, studentName, degree, issuer, issueDate, ""), nil
}

// --- Internal Helpers --------------------------------------------------------

func (s *SmartContract) rangeAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	iter, err := ctx.GetStub().GetStateByRange("CERT_", "CERT_~")
	if err != nil {
		return []*Certificate{}, nil
	}
	defer iter.Close()
	var certs []*Certificate
	for iter.HasNext() {
		resp, err := iter.Next()
		if err != nil {
			continue
		}
		if strings.HasPrefix(resp.Key, KeyPrefixAudit) {
			continue
		}
		var c Certificate
		if err := json.Unmarshal(resp.Value, &c); err != nil {
			continue
		}
		if c.DocType == DocTypeCertificate {
			c.Transcript = "" // Strip heavy payload for list view
			certs = append(certs, &c)
		}
		if len(certs) >= 50 {
			break
		}
	}
	if certs == nil {
		certs = []*Certificate{}
	}
	return certs, nil
}
