// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode Implementation — SHA-256 Mode  (v12.0 — PhD RESEARCH EDITION)
//
//  CHANGES vs v11:
//  ─────────────────────────────────────────────────────────────────────────
//  FIX-DEADCODE:   Removed ComputeCertHashSHA256 (defined but never called).
//                  ComputeCertHash is the single authoritative hash entry
//                  point — matches BLAKE3 v12 structure exactly.
//
//  FIX-ERRORS:     RevokeCertificate now handles all errors explicitly:
//                  GetState, Unmarshal, Marshal, and PutState failures are
//                  returned as errors instead of being silently discarded.
//                  Matches BLAKE3 v12 error handling exactly.
//
//  FIX-AUDIT:      Uncommented writeAudit in IssueCertificate. The audit
//                  trail now covers ISSUE and REVOKE operations — consistent
//                  with BLAKE3 v12 and the security design requirements.
//
//  FIX-EXTRA:      Removed getCallerRole helper (defined but never used in
//                  any access control decision). Not present in BLAKE3 v12.
//
//  FIX-MAIN:       Added main() with contractapi.NewChaincode entry point.
//                  Required for standalone chaincode deployment.
//
//  FIX-MVCC:       IssueCertificate now checks the GetState error explicitly
//                  instead of discarding it with _.
//
//  MAGNIFICATION JUSTIFICATION (k = 100):
//  ─────────────────────────────────────────────────────────────────────────
//  Identical to BLAKE3 v12: the magnification factor k=100 amplifies the
//  ~11 µs per-hash Δ between SHA-256 and BLAKE3 into a detectable signal
//  within Hyperledger Caliper's measurement resolution. The output is
//  deterministic since identical input bytes are supplied on every iteration.
//  In production deployment this constant would be set to 1.
//
//  INHERITED FIXES FROM v11:
//  ─────────────────────────────────────────────────────────────────────────
//  FIX-INDEX-1: Seeds use CERT_ prefix (range-query safe).
//  FIX-INDEX-2: CouchDB index selector includes "issueDate":{"$gt":null}.
//  FIX-MVCC:    IssueCertificate is idempotent.
//  FIX-AUDIT:   Audit key uses AUDIT_{txID}_{certID} composite pattern.
//  v11-PARITY:  VerifyCertificate hashes cert.Transcript (real payload).
//  v11-PARITY:  RevokeCertificate is flag-only (no re-hash).
//
//  SHA-256 ALGORITHM PROPERTIES:
//  ─────────────────────────────────────────────────────────────────────────
//  SHA-256 uses a Merkle-Damgård sequential construction:
//    - Every 512-bit input block is processed through 64 compression rounds
//    - Strictly sequential — no inter-block parallelism possible
//    - No SIMD acceleration in the Go standard library crypto/sha256
//    - Output: 256 bits (32 bytes)
//    - Security: 2^128 collision resistance
//
//  Benchmark (5 KB payload, experimental environment hardware):
//    SHA-256:  15.0 µs/hash — 66,653 hashes/sec
//    (Compare: BLAKE3: 4.01 µs/hash — 249,464 hashes/sec — 3.74× faster)
//
//  This establishes SHA-256 as the performance BASELINE (T₁) against which
//  all other configurations are measured. Any Caliper result showing higher
//  throughput or lower latency in Scenarios 2–4 constitutes evidence for
//  the research hypothesis T₄ < T₃ < T₂ < T₁.
// ============================================================================

package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// HashModeSHA256 identifies the SHA-256 hash algorithm.
// Stored in every certificate record alongside the digest.
const HashModeSHA256 = "sha256"

// MagnificationFactor controls the number of hash iterations per invocation.
// Identical to BLAKE3 v12 — ensures symmetric benchmark amplification.
// In production deployment this constant would be set to 1.
const MagnificationFactor = 100

// ─── Data Structures ────────────────────────────────────────────────────────

// Certificate is the primary ledger asset representing one academic credential.
type Certificate struct {
	DocType     string `json:"docType"`
	ID          string `json:"id"`
	StudentID   string `json:"studentID"`
	StudentName string `json:"studentName"`
	Degree      string `json:"degree"`
	Issuer      string `json:"issuer"`
	IssueDate   string `json:"issueDate"`
	CertHash    string `json:"certHash"`
	HashAlgo    string `json:"hashAlgo"`
	Signature   string `json:"signature"`
	Transcript  string `json:"transcript,omitempty"`
	IsRevoked   bool   `json:"isRevoked"`
	RevokedBy   string `json:"revokedBy"`
	RevokedAt   string `json:"revokedAt"`
	CreatedAt   string `json:"createdAt"`
	UpdatedAt   string `json:"updatedAt"`
	TxID        string `json:"txID"`
}

// VerificationResult is the read-only response returned by VerifyCertificate.
type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	HashAlgo  string `json:"hashAlgo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

// PaginatedQueryResult wraps a certificate list query with bookmark support.
type PaginatedQueryResult struct {
	Certificates []*Certificate `json:"certificates"`
	Bookmark     string         `json:"bookmark"`
	Count        int            `json:"count"`
}

// AuditLog is written for every mutating operation (ISSUE, REVOKE).
// Stored under key pattern: AUDIT_{txID}_{certID}
type AuditLog struct {
	DocType   string `json:"docType"`
	TxID      string `json:"txID"`
	CertID    string `json:"certID"`
	Action    string `json:"action"`
	Actor     string `json:"actor"`
	Timestamp string `json:"timestamp"`
	Detail    string `json:"detail"`
}

// SmartContract embeds contractapi.Contract and exposes all chaincode functions.
type SmartContract struct {
	contractapi.Contract
}

// ─── SHA-256 Hash Engine ─────────────────────────────────────────────────────
//
// ComputeCertHash is the single authoritative hash entry point for the SHA-256
// configuration. It builds the certificate payload by joining the six credential
// fields with a pipe delimiter, converts to bytes, and computes the SHA-256 hash
// MagnificationFactor times to produce a measurable benchmark signal.
//
// This function is structurally IDENTICAL to BLAKE3 v12's ComputeCertHash,
// differing only in the hash primitive called:
//   SHA-256:  hash = sha256.Sum256(data)   — 15.0 µs per call
//   BLAKE3:   hash = blake3.Sum256(data)   —  4.01 µs per call
//
// This structural identity is the scientific foundation of the fair comparison:
// any performance difference measured by Caliper is attributable exclusively
// to the hash algorithm, not to any other implementation asymmetry.
//
// Output: (hexadecimal 256-bit digest, algorithm identifier "sha256")

func ComputeCertHash(
	studentID, studentName, degree, issuer, issueDate, transcript string,
) (string, string) {

	// Step 1: Build the canonical payload string.
	// Fields joined with "|" — identical delimiter to BLAKE3 v12.
	parts := []string{studentID, studentName, degree, issuer, issueDate}
	if transcript != "" {
		parts = append(parts, transcript)
	}
	data := []byte(strings.Join(parts, "|"))

	// Step 2: Magnification loop (k = MagnificationFactor = 100).
	// Identical structure to BLAKE3 v12 — amplifies the per-hash latency
	// differential into a Caliper-detectable signal.
	// SHA-256: 15.0 µs × 100 = 1,500 µs per transaction
	// BLAKE3:   4.01 µs × 100 =   401 µs per transaction
	// Δ = 1,099 µs per transaction — detectable at ≥ 100 TPS
	var hash [32]byte
	for i := 0; i < MagnificationFactor; i++ {
		hash = sha256.Sum256(data) // SHA-256: sequential, no SIMD
	}

	return fmt.Sprintf("%x", hash), HashModeSHA256
}

// ─── Identity Helper ────────────────────────────────────────────────────────

// getCallerMSP retrieves the MSP ID of the transaction submitter.
// Identical implementation to BLAKE3 v12.
func getCallerMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("failed to read client MSP ID: %v", err)
	}
	return mspID, nil
}

// ─── Audit Trail ────────────────────────────────────────────────────────────

// writeAudit creates a distinct audit log record for every mutating transaction.
// Key pattern: AUDIT_{txID}_{certID} — identical to BLAKE3 v12.
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

	data, err := json.Marshal(log)
	if err != nil {
		fmt.Printf("writeAudit: marshal error for cert %s: %v\n", certID, err)
		return
	}
	if err := ctx.GetStub().PutState(key, data); err != nil {
		fmt.Printf("writeAudit: PutState error for key %s: %v\n", key, err)
	}
}

// ─── InitLedger ─────────────────────────────────────────────────────────────

// InitLedger seeds the ledger with five predefined certificate records.
// FIX-INDEX-1: Seeds use "CERT_" prefix for range-query compatibility.
// Access: Org1MSP only.
func (s *SmartContract) InitLedger(
	ctx contractapi.TransactionContextInterface,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("InitLedger: %v", err)
	}
	if mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can initialize ledger")
	}

	type seedCert struct {
		id, studentID, studentName, degree, issuer, issueDate string
	}

	seeds := []seedCert{
		{"CERT_SEED_001", "STU001", "Alice Johnson", "Bachelor of Computer Science", "Digital University", "2024-01-15"},
		{"CERT_SEED_002", "STU002", "Bob Smith", "Master of Data Science", "Tech Institute", "2024-02-20"},
		{"CERT_SEED_003", "STU003", "Carol Williams", "PhD in Artificial Intelligence", "Research Academy", "2024-03-10"},
		{"CERT_SEED_004", "STU004", "David Brown", "Bachelor of Engineering", "Engineering College", "2024-04-05"},
		{"CERT_SEED_005", "STU005", "Eve Davis", "MBA in Business Administration", "Business School", "2024-05-12"},
	}

	for _, seed := range seeds {
		certHash, hashAlgo := ComputeCertHash(
			seed.studentID, seed.studentName,
			seed.degree, seed.issuer, seed.issueDate, "",
		)

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
			Signature:   fmt.Sprintf("SIG_%s_%s", seed.id, certHash[:8]),
			Transcript:  "",
			IsRevoked:   false,
			RevokedBy:   "N/A",
			RevokedAt:   "N/A",
			CreatedAt:   time.Now().UTC().Format(time.RFC3339),
			UpdatedAt:   time.Now().UTC().Format(time.RFC3339),
			TxID:        ctx.GetStub().GetTxID(),
		}

		certJSON, err := json.Marshal(cert)
		if err != nil {
			return fmt.Errorf("InitLedger: marshal failed for %s: %v", seed.id, err)
		}
		if err := ctx.GetStub().PutState(seed.id, certJSON); err != nil {
			return fmt.Errorf("InitLedger: PutState failed for %s: %v", seed.id, err)
		}
	}

	return nil
}

// ─── IssueCertificate ───────────────────────────────────────────────────────
//
// IssueCertificate is the primary write operation — the SHA-256 performance
// baseline for the IssueCertificate Caliper workload.
//
// SHA-256 characteristic at this operation: hash computation at 15.0 µs
// creates higher CPU contention under concurrent write loads than BLAKE3
// (4.01 µs) — the predicted source of latency advantage in Scenario 2.
//
// FIX-MVCC: idempotent — duplicate IDs return nil without error.
// FIX-AUDIT (v12.0): writeAudit is now active.
// Access: Org1MSP only.
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id, studentID, studentName, degree, issuer, issueDate,
	certHash, blake3Hash, signature, batchID, transcript string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("IssueCertificate: %v", err)
	}
	if mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can issue certificates")
	}

	if id == "" || studentID == "" || studentName == "" ||
		degree == "" || issuer == "" || issueDate == "" {
		return fmt.Errorf("validation error: id, studentID, studentName, degree, issuer, and issueDate are required")
	}

	// FIX-MVCC (v12): explicit error check (previously discarded with _).
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("IssueCertificate: GetState failed: %v", err)
	}
	if existing != nil {
		return nil // Duplicate — idempotent return.
	}

	computedHash, hashAlgo := ComputeCertHash(
		studentID, studentName, degree, issuer, issueDate, transcript,
	)
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
		return fmt.Errorf("IssueCertificate: marshal failed: %v", err)
	}
	if err := ctx.GetStub().PutState(id, certJSON); err != nil {
		return fmt.Errorf("IssueCertificate: PutState failed: %v", err)
	}

	// FIX-AUDIT (v12.0): now active — matches BLAKE3 v12 audit behaviour.
	s.writeAudit(ctx, id, "ISSUE", issuer,
		fmt.Sprintf("SHA-256 issue | batch: %s | hashAlgo: %s", batchID, hashAlgo))

	return nil
}

// ─── VerifyCertificate ──────────────────────────────────────────────────────
//
// VerifyCertificate is the performance-critical read operation — the function
// where the SHA-256 vs BLAKE3 latency difference is most measurable at high TPS.
//
// CPU cost at 800 TPS (with MagnificationFactor = 100):
//   SHA-256:  1,500 µs × 800 = 1,200,000 µs/sec per peer  ← this function
//   BLAKE3:     401 µs × 800 =   320,800 µs/sec per peer
//   Saving:   ≈ 879,200 µs/sec when using BLAKE3 (Scenario 2)
//
// FIX-PERF (v11): No MSP role check — identical to BLAKE3 v12.
// Access: open to all participants.
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id, certHash string,
) (*VerificationResult, error) {
	ts := time.Now().UTC().Format(time.RFC3339)

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return &VerificationResult{
			CertID: id, Valid: false,
			Message:   fmt.Sprintf("ledger read error: %v", err),
			HashAlgo:  HashModeSHA256, Timestamp: ts,
		}, nil
	}
	if certJSON == nil {
		return &VerificationResult{
			CertID: id, Valid: false,
			Message:   "certificate not found",
			HashAlgo:  HashModeSHA256, Timestamp: ts,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return &VerificationResult{
			CertID: id, Valid: false,
			Message:   "corrupt certificate data in ledger",
			HashAlgo:  HashModeSHA256, Timestamp: ts,
		}, nil
	}

	// Re-compute hash from stored plaintext — SHA-256 at 15.0 µs × 100 = 1,500 µs.
	// vs BLAKE3 at 4.01 µs × 100 = 401 µs. The 1,099 µs difference per call
	// accumulates to ~879,200 µs/sec CPU freed at 800 TPS when using BLAKE3.
	// v11-PARITY: cert.Transcript is included (real payload, not empty string).
	computed, _ := ComputeCertHash(
		cert.StudentID, cert.StudentName,
		cert.Degree, cert.Issuer, cert.IssueDate, cert.Transcript,
	)

	isValid := cert.CertHash == computed
	if certHash != "" && certHash != computed {
		isValid = false
	}

	if cert.IsRevoked {
		return &VerificationResult{
			CertID: id, Valid: false, IsRevoked: true, HashMatch: isValid,
			HashAlgo:  HashModeSHA256,
			Message:   "certificate has been revoked",
			Timestamp: ts,
		}, nil
	}

	if !isValid {
		return &VerificationResult{
			CertID: id, Valid: false, HashMatch: false,
			HashAlgo:  HashModeSHA256,
			Message:   "hash mismatch — certificate may have been tampered with",
			Timestamp: ts,
		}, nil
	}

	return &VerificationResult{
		CertID: id, Valid: true, IsRevoked: false, HashMatch: true,
		HashAlgo:  HashModeSHA256,
		Message:   "certificate is valid and authentic (SHA-256 verified)",
		Timestamp: ts,
	}, nil
}

// ─── VerifyCertificateByID ──────────────────────────────────────────────────

// VerifyCertificateByID retrieves the stored hash and delegates to VerifyCertificate.
func (s *SmartContract) VerifyCertificateByID(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*VerificationResult, error) {
	cert, err := s.GetCertificate(ctx, id)
	if err != nil {
		ts := time.Now().UTC().Format(time.RFC3339)
		return &VerificationResult{
			CertID: id, Valid: false,
			Message:   fmt.Sprintf("verification failed: %v", err),
			HashAlgo:  HashModeSHA256, Timestamp: ts,
		}, nil
	}
	return s.VerifyCertificate(ctx, id, cert.CertHash)
}

// ─── GetCertificate / ReadCertificate ───────────────────────────────────────

// GetCertificate performs a point-to-point key lookup in the CouchDB world state.
func (s *SmartContract) GetCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*Certificate, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("GetCertificate: ledger read error: %v", err)
	}
	if certJSON == nil {
		return nil, fmt.Errorf("GetCertificate: certificate %s does not exist", id)
	}

	var cert Certificate
	if err = json.Unmarshal(certJSON, &cert); err != nil {
		return nil, fmt.Errorf("GetCertificate: unmarshal error: %v", err)
	}
	return &cert, nil
}

// ReadCertificate is an alias for GetCertificate (REST API compatibility).
func (s *SmartContract) ReadCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*Certificate, error) {
	return s.GetCertificate(ctx, id)
}

// ─── RevokeCertificate ──────────────────────────────────────────────────────
//
// RevokeCertificate permanently invalidates a certificate by toggling isRevoked.
//
// v11-PARITY: Flag-only update — no hash recomputation. Identical logic to
// BLAKE3 v12 RevokeCertificate. Both perform: read → check → update → write.
//
// FIX-ERRORS (v12.0): All GetState, Unmarshal, Marshal, and PutState errors
// are now returned explicitly — matches BLAKE3 v12 exactly.
//
// Idempotency: already-revoked certificates return nil without error.
// Access: Org1MSP and Org2MSP.
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	msp, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: %v", err)
	}
	if msp != "Org1MSP" && msp != "Org2MSP" {
		return fmt.Errorf("access denied: only Org1MSP or Org2MSP can revoke certificates")
	}

	// FIX-ERRORS: explicit error check (previously discarded with _).
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: GetState failed: %v", err)
	}
	if certJSON == nil {
		return nil // Not found — idempotent return.
	}

	// FIX-ERRORS: explicit error check on unmarshal (previously discarded).
	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return fmt.Errorf("RevokeCertificate: unmarshal failed: %v", err)
	}

	if cert.IsRevoked {
		return nil // Already revoked — idempotent return.
	}

	// v11-PARITY: No hash recomputation here.
	// Revocation is a STATUS FLAG UPDATE only — not a verification event.
	// SHA-256 and BLAKE3 perform identical work at this step:
	// read → check flag → update flag → write state → write audit.
	cert.IsRevoked = true
	cert.RevokedBy = msp
	cert.RevokedAt = time.Now().UTC().Format(time.RFC3339)
	cert.UpdatedAt = time.Now().UTC().Format(time.RFC3339)

	// FIX-ERRORS: explicit error check on marshal (previously discarded with _).
	updated, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("RevokeCertificate: marshal failed: %v", err)
	}

	// FIX-ERRORS: explicit error check on PutState (previously unchecked).
	if err := ctx.GetStub().PutState(id, updated); err != nil {
		return fmt.Errorf("RevokeCertificate: PutState failed: %v", err)
	}

	s.writeAudit(ctx, id, "REVOKE", msp, "SHA-256 revoke — flag update, no re-hash (v11-PARITY)")
	return nil
}

// ─── QueryAllCertificates ───────────────────────────────────────────────────
//
// QueryAllCertificates returns a paginated list of active certificate assets.
//
// FIX-INDEX-2: Selector includes "issueDate":{"$gt":null} so CouchDB can use
// the compound index (indexDocTypeIssueDate) — identical to BLAKE3 v12.
// FIX-QUERY: pageSize default = 20 — identical to BLAKE3 v12.
//
// This operation is I/O-bound (CouchDB). The hash algorithm has zero impact.
// Any latency difference between C1 and C2 in this workload is CouchDB/network
// variance and must not be attributed to the hash algorithm.
func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
	pageSize string,
	bookmark string,
) (string, error) {
	queryString := `{
		"selector": {
			"docType": "certificate",
			"issueDate": { "$gt": null }
		},
		"sort": [{ "issueDate": "desc" }]
	}`

	ps, err := strconv.ParseInt(pageSize, 10, 32)
	if err != nil || ps <= 0 {
		ps = 20 // FIX-QUERY: consistent default — matches BLAKE3 v12.
	}

	resultsIterator, metadata, err := ctx.GetStub().GetQueryResultWithPagination(
		queryString, int32(ps), bookmark,
	)
	if err != nil {
		return s.queryAllByRange(ctx, int(ps))
	}
	defer resultsIterator.Close()

	certificates := make([]*Certificate, 0)
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		if cert.DocType == "certificate" {
			cert.Transcript = "" // Strip payload — minimise bandwidth.
			certificates = append(certificates, &cert)
		}
	}

	res := &PaginatedQueryResult{
		Certificates: certificates,
		Bookmark:     metadata.Bookmark,
		Count:        len(certificates),
	}
	resJSON, err := json.Marshal(res)
	if err != nil {
		return "", fmt.Errorf("QueryAllCertificates: marshal response failed: %v", err)
	}
	return string(resJSON), nil
}

// queryAllByRange is the fallback range scan when CouchDB rich queries fail.
func (s *SmartContract) queryAllByRange(
	ctx contractapi.TransactionContextInterface,
	limit int,
) (string, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("CERT_", "CERT_~")
	if err != nil {
		return `{"certificates":[],"bookmark":"","count":0}`, nil
	}
	defer resultsIterator.Close()

	certificates := make([]*Certificate, 0)
	count := 0
	for resultsIterator.HasNext() && count < limit {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			continue
		}
		if cert.DocType == "certificate" {
			cert.Transcript = ""
			certificates = append(certificates, &cert)
			count++
		}
	}

	res := &PaginatedQueryResult{
		Certificates: certificates,
		Bookmark:     "",
		Count:        len(certificates),
	}
	resJSON, err := json.Marshal(res)
	if err != nil {
		return `{"certificates":[],"bookmark":"","count":0}`, nil
	}
	return string(resJSON), nil
}

// ─── GetCertificatesByStudent ────────────────────────────────────────────────

// GetCertificatesByStudent retrieves all certificates for a specific student.
func (s *SmartContract) GetCertificatesByStudent(
	ctx contractapi.TransactionContextInterface,
	studentID string,
) ([]*Certificate, error) {
	if studentID == "" {
		return []*Certificate{}, fmt.Errorf("studentID is required")
	}

	queryString := fmt.Sprintf(
		`{"selector":{"docType":"certificate","studentID":"%s","issueDate":{"$gt":null}},"sort":[{"issueDate":"desc"}]}`,
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
		if err := json.Unmarshal(queryResponse.Value, &cert); err == nil {
			if cert.DocType == "certificate" {
				certificates = append(certificates, &cert)
			}
		}
	}
	return certificates, nil
}

// ─── GetAuditLogs ────────────────────────────────────────────────────────────

// GetAuditLogs returns the 50 most recent audit records sorted by timestamp.
func (s *SmartContract) GetAuditLogs(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	queryString := `{
		"selector": {
			"docType": "auditLog",
			"timestamp": { "$gt": null }
		},
		"sort": [{ "timestamp": "desc" }],
		"limit": 50
	}`

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil || resultsIterator == nil {
		return s.getAuditLogsByRange(ctx)
	}
	defer resultsIterator.Close()

	var logs []*AuditLog
	count := 0
	for resultsIterator.HasNext() && count < 50 {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var log AuditLog
		if err = json.Unmarshal(queryResponse.Value, &log); err == nil {
			logs = append(logs, &log)
			count++
		}
	}
	return logs, nil
}

// getAuditLogsByRange is the fallback range scan for audit records.
func (s *SmartContract) getAuditLogsByRange(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("AUDIT_", "AUDIT_~")
	if err != nil {
		return []*AuditLog{}, nil
	}
	defer resultsIterator.Close()

	var logs []*AuditLog
	count := 0
	for resultsIterator.HasNext() && count < 50 {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		var log AuditLog
		if err = json.Unmarshal(queryResponse.Value, &log); err == nil {
			logs = append(logs, &log)
			count++
		}
	}
	return logs, nil
}

// ─── Utility Functions ───────────────────────────────────────────────────────

// ComputeHash is the public Caliper benchmark endpoint.
// Exercises SHA-256 hash computation without writing to the ledger.
// This is the primary workload invoked by the Caliper ComputeHash module
// for Scenario 1. The SHA-256 result establishes the T₁ baseline.
func (s *SmartContract) ComputeHash(
	ctx contractapi.TransactionContextInterface,
	studentID, studentName, degree, issuer, issueDate string,
) (string, error) {
	if studentID == "" || studentName == "" || degree == "" ||
		issuer == "" || issueDate == "" {
		return "", fmt.Errorf("all five fields are required for hash computation")
	}

	hash, _ := ComputeCertHash(studentID, studentName, degree, issuer, issueDate, "")
	return hash, nil
}

// GetHashAlgorithm returns the algorithm identifier for this chaincode instance.
func (s *SmartContract) GetHashAlgorithm(
	ctx contractapi.TransactionContextInterface,
) (string, error) {
	return HashModeSHA256, nil
}

// ─── Main ────────────────────────────────────────────────────────────────────

func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		panic(fmt.Sprintf("Error creating BCMS SHA-256 chaincode: %v", err))
	}
	if err := chaincode.Start(); err != nil {
		panic(fmt.Sprintf("Error starting BCMS SHA-256 chaincode: %v", err))
	}
}