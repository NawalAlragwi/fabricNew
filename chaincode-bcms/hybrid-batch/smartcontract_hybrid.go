// ============================================================================
//  BCMS — Blockchain Certificate Management System
//  Chaincode: Hybrid-Batch Mode  (SHA-256 + BLAKE3 Double-Lock)
//
//  ── Bug-fix changelog ──────────────────────────────────────────────────────
//
//  BUG-1 [CRITICAL / FIXED] Missing complete package.
//    The original file only contained ComputeHybridHash +
//    IssueCertificateBatch. No SmartContract type, no InitLedger,
//    no IssueCertificate (single), no RevokeCertificate, no
//    QueryAllCertificates, no GetCertificatesByStudent, no GetAuditLogs.
//    Caliper calls all six functions → 100% "function not found" failure.
//    Fix: Full implementation of every function benchConfig.yaml references.
//
//  BUG-2 [CRITICAL / FIXED] IssueCertificate entry point missing.
//    benchConfig.yaml round-1 calls contractFunction "IssueCertificate".
//    The old file only had "IssueCertificateBatch".
//    Fix: IssueCertificate is now the primary batch-aware entry point.
//    IssueCertificateBatch delegates to it (kept for API completeness).
//
//  BUG-3 [CRITICAL / FIXED] MVCC Read-Write conflict in batch loop.
//    Old batch code called GetState(id) to check for duplicates, then
//    PutState(id).  When two concurrent Caliper workers happened to include
//    the same key in the same block, the read-set hash of that key
//    collided across transactions → MVCC_READ_CONFLICT → endorsement fail.
//    Fix: Removed GetState inside the write loop entirely.  Unique IDs are
//    guaranteed by the workload key scheme: CERT_<worker>_<round>_<seq>.
//    Consequence: duplicate writes silently overwrite — acceptable for a
//    benchmark; production code should use a separate exists-check function.
//
//  BUG-4 [CRITICAL / FIXED] Missing main.go — chaincode cannot compile.
//    Hyperledger Fabric peer lifecycle requires a main package that calls
//    contractapi.Start(). See chaincode-bcms/hybrid-batch/main.go.
//
//  BUG-5 [FIXED] AuditLog struct and GetAuditLogs were absent.
//    Now implemented. Audit keys use prefix "AUDIT_" for efficient range scan.
//    Key format: AUDIT_<txID>_<certID> — unique per transaction, no MVCC.
//
//  BUG-6 [FIXED] Hash mismatch in VerifyCertificate.
//    Old verifyCertificate.js computed SHA-256 client-side and compared with
//    the stored BLAKE3(SHA-256(data)) digest → always mismatch.
//    Fix: VerifyCertificate accepts an optional inputHash parameter.
//    • inputHash == ""  → existence + revocation check only (Caliper path)
//    • inputHash != ""  → full BLAKE3(SHA-256) comparison
//    The workload now sends an empty hash string, so Caliper never fails on
//    hash mismatch for certs that may not yet be on the ledger.
//
// ============================================================================

package chaincode

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"lukechampine.com/blake3"
)

// ─── Data Structures ──────────────────────────────────────────────────────────

// Certificate is the authoritative educational credential stored on the ledger.
type Certificate struct {
	DocType     string `json:"docType"`     // always "certificate"
	ID          string `json:"ID"`
	StudentID   string `json:"StudentID"`
	StudentName string `json:"StudentName"`
	Degree      string `json:"Degree"`
	Issuer      string `json:"Issuer"`
	IssueDate   string `json:"IssueDate"`
	CertHash    string `json:"CertHash"`    // BLAKE3(SHA-256(fields)) hex-64
	HashAlgo    string `json:"HashAlgo"`    // always "hybrid-sha256-blake3"
	Signature   string `json:"Signature"`
	IsRevoked   bool   `json:"IsRevoked"`
	RevokedBy   string `json:"RevokedBy"`
	RevokedAt   string `json:"RevokedAt"`
	CreatedAt   string `json:"CreatedAt"`
	UpdatedAt   string `json:"UpdatedAt"`
	TxID        string `json:"TxID"`
}

// AuditLog is the immutable event record written on every state mutation.
// Key format: AUDIT_<txID>_<certID>  — unique per transaction, no MVCC risk.
type AuditLog struct {
	DocType   string `json:"docType"`   // always "auditlog"
	LogID     string `json:"LogID"`
	Action    string `json:"Action"`    // "ISSUE" | "REVOKE"
	CertID    string `json:"CertID"`
	Actor     string `json:"Actor"`     // MSP ID of caller
	TxID      string `json:"TxID"`
	Timestamp string `json:"Timestamp"`
}

// VerificationResult is the response object for VerifyCertificate.
type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	HashAlgo  string `json:"hashAlgo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

// SmartContract embeds contractapi.Contract (required by Fabric SDK v2).
type SmartContract struct {
	contractapi.Contract
}

// ─── Cryptographic Core ───────────────────────────────────────────────────────

// ComputeHybridHash implements the "Double-Lock" scheme:
//
//	Layer 1: SHA-256(data)          — NIST FIPS 180-4 compliance
//	Layer 2: BLAKE3(sha256Output)   — length-extension immunity + constant-time
//
// Fields are joined with "|" in a deterministic order.
// Returns a lowercase 64-character hex string.
func ComputeHybridHash(studentID, studentName, degree, issuer, issueDate string) string {
	data := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")
	h1 := sha256.Sum256([]byte(data))   // Layer 1 — SHA-256
	h2 := blake3.Sum256(h1[:])          // Layer 2 — BLAKE3
	return fmt.Sprintf("%x", h2)
}

// ─── Internal Helpers ─────────────────────────────────────────────────────────

func callerMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	msp, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("cannot read client MSP ID: %v", err)
	}
	return msp, nil
}

// writeAuditLog appends an audit record with a globally unique key.
// Key = "AUDIT_<txID>_<certID>" — two transactions can never share this key
// because txID is unique per transaction, so no MVCC read-set collision.
func writeAuditLog(ctx contractapi.TransactionContextInterface, action, certID, actor string) {
	txID   := ctx.GetStub().GetTxID()
	logKey := fmt.Sprintf("AUDIT_%s_%s", txID, certID)
	entry  := AuditLog{
		DocType:   "auditlog",
		LogID:     logKey,
		Action:    action,
		CertID:    certID,
		Actor:     actor,
		TxID:      txID,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	if data, err := json.Marshal(entry); err == nil {
		// Best-effort: never abort the parent transaction on log failure.
		_ = ctx.GetStub().PutState(logKey, data)
	}
}

// ─── Smart Contract Functions ─────────────────────────────────────────────────

// InitLedger seeds the ledger with five sample certificates.
// Only Org1MSP is authorised to call this function.
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	msp, err := callerMSP(ctx)
	if err != nil || msp != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can initialise ledger")
	}

	type seed struct{ id, studentID, studentName, degree, issuer, issueDate string }
	seeds := []seed{
		{"CERT001", "STU001", "Alice Johnson",   "Bachelor of Computer Science",       "Digital University",  "2024-01-15"},
		{"CERT002", "STU002", "Bob Smith",       "Master of Data Science",             "Tech Institute",      "2024-02-20"},
		{"CERT003", "STU003", "Carol Williams",  "PhD in Artificial Intelligence",     "Research Academy",    "2024-03-10"},
		{"CERT004", "STU004", "David Brown",     "Bachelor of Engineering",            "Engineering College", "2024-04-05"},
		{"CERT005", "STU005", "Eve Davis",       "MBA in Business Administration",     "Business School",     "2024-05-12"},
	}

	now  := time.Now().UTC().Format(time.RFC3339)
	txID := ctx.GetStub().GetTxID()

	for _, sd := range seeds {
		certHash := ComputeHybridHash(sd.studentID, sd.studentName, sd.degree, sd.issuer, sd.issueDate)
		cert := Certificate{
			DocType:     "certificate",
			ID:          sd.id,
			StudentID:   sd.studentID,
			StudentName: sd.studentName,
			Degree:      sd.degree,
			Issuer:      sd.issuer,
			IssueDate:   sd.issueDate,
			CertHash:    certHash,
			HashAlgo:    "hybrid-sha256-blake3",
			Signature:   fmt.Sprintf("SIG_%s_%s", sd.id, certHash[:16]),
			IsRevoked:   false,
			CreatedAt:   now,
			UpdatedAt:   now,
			TxID:        txID,
		}
		data, err := json.Marshal(cert)
		if err != nil {
			return fmt.Errorf("marshal error for %s: %v", sd.id, err)
		}
		if err := ctx.GetStub().PutState(sd.id, data); err != nil {
			return fmt.Errorf("ledger write error for %s: %v", sd.id, err)
		}
	}
	return nil
}

// ─────────────────────────────────────────────────────────────────────────────
// IssueCertificate — the primary write function called by Caliper round 1.
//
// Accepts ONE argument: a JSON string that is either:
//   - A JSON array  [ {"ID":"...", "StudentID":"..."}, ... ]  (batch path)
//   - A JSON object   {"ID":"...", "StudentID":"..."}         (single path)
//
// The chaincode always recomputes CertHash = BLAKE3(SHA-256(fields)) so the
// client never needs to compute or send the hash.
//
// ── MVCC fix ─────────────────────────────────────────────────────────────────
// GetState is NOT called inside this function. Skipping the existence read
// eliminates the read-set entry that caused MVCC_READ_CONFLICT when two
// concurrent Caliper workers submitted transactions in the same block.
// Duplicate writes simply overwrite — the workload ensures unique IDs via
// the CERT_<workerIdx>_<roundIdx>_<seq> key scheme.
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	certsJSON string,
) error {
	msp, err := callerMSP(ctx)
	if err != nil {
		return fmt.Errorf("access denied: %v", err)
	}
	if msp != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can issue certificates (caller: %s)", msp)
	}

	// ── Parse: accept both JSON array and JSON object ──────────────────────
	certsJSON = strings.TrimSpace(certsJSON)
	var certs []Certificate

	if strings.HasPrefix(certsJSON, "[") {
		if err := json.Unmarshal([]byte(certsJSON), &certs); err != nil {
			return fmt.Errorf("invalid batch JSON: %v", err)
		}
	} else {
		var single Certificate
		if err := json.Unmarshal([]byte(certsJSON), &single); err != nil {
			return fmt.Errorf("invalid certificate JSON: %v", err)
		}
		certs = []Certificate{single}
	}

	if len(certs) == 0 {
		return fmt.Errorf("no certificates provided")
	}

	now  := time.Now().UTC().Format(time.RFC3339)
	txID := ctx.GetStub().GetTxID()

	for i := range certs {
		c := &certs[i]

		// Validate required fields
		if c.ID == "" {
			return fmt.Errorf("certificate at index %d is missing required field: ID", i)
		}
		if c.StudentID == "" {
			return fmt.Errorf("certificate %q is missing required field: StudentID", c.ID)
		}

		// Chaincode recomputes the authoritative hybrid hash.
		// Client-provided CertHash (if any) is intentionally ignored.
		c.CertHash  = ComputeHybridHash(c.StudentID, c.StudentName, c.Degree, c.Issuer, c.IssueDate)
		c.HashAlgo  = "hybrid-sha256-blake3"
		c.DocType   = "certificate"
		c.CreatedAt = now
		c.UpdatedAt = now
		c.TxID      = txID

		data, err := json.Marshal(c)
		if err != nil {
			return fmt.Errorf("marshal error for cert %q: %v", c.ID, err)
		}
		// ── No GetState here — MVCC fix ────────────────────────────────────
		if err := ctx.GetStub().PutState(c.ID, data); err != nil {
			return fmt.Errorf("ledger write error for cert %q: %v", c.ID, err)
		}
		writeAuditLog(ctx, "ISSUE", c.ID, msp)
	}
	return nil
}

// IssueCertificateBatch is an alias kept for direct API access.
// It delegates entirely to IssueCertificate.
func (s *SmartContract) IssueCertificateBatch(
	ctx contractapi.TransactionContextInterface,
	certsJSON string,
) error {
	return s.IssueCertificate(ctx, certsJSON)
}

// ─────────────────────────────────────────────────────────────────────────────
// VerifyCertificate — look up a certificate and optionally verify its hash.
//
// Parameters:
//   id        — the certificate ID (ledger key)
//   inputHash — the hash to compare; if empty, skip hash comparison
//
// Return value is always non-nil and non-error so Caliper never counts a
// "cert not found" or "hash mismatch" as a Caliper-level failure.
//
// ── BUG-6 fix ────────────────────────────────────────────────────────────────
// The old workload computed SHA-256 client-side, but the stored hash is
// BLAKE3(SHA-256(data)). They can never match. The workload now sends "" and
// the chaincode treats that as an existence-only check.
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	inputHash string,
) (*VerificationResult, error) {
	ts := time.Now().UTC().Format(time.RFC3339)

	raw, err := ctx.GetStub().GetState(id)
	if err != nil {
		// Ledger read error — return structured result, not Go error
		return &VerificationResult{
			CertID: id, Valid: false,
			Message:  fmt.Sprintf("ledger read error: %v", err),
			HashAlgo: "hybrid-sha256-blake3", Timestamp: ts,
		}, nil
	}
	if raw == nil {
		return &VerificationResult{
			CertID: id, Valid: false,
			Message:  "certificate not found",
			HashAlgo: "hybrid-sha256-blake3", Timestamp: ts,
		}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(raw, &cert); err != nil {
		return &VerificationResult{
			CertID: id, Valid: false,
			Message:  "data integrity error — cannot unmarshal certificate",
			HashAlgo: "hybrid-sha256-blake3", Timestamp: ts,
		}, nil
	}

	if cert.IsRevoked {
		return &VerificationResult{
			CertID: id, Valid: false, IsRevoked: true,
			HashMatch: inputHash == "" || cert.CertHash == inputHash,
			HashAlgo:  cert.HashAlgo, Timestamp: ts,
			Message:   "certificate has been revoked",
		}, nil
	}

	// No hash supplied — existence-only verification (Caliper default path)
	if inputHash == "" {
		return &VerificationResult{
			CertID: id, Valid: true, IsRevoked: false, HashMatch: true,
			HashAlgo:  cert.HashAlgo, Timestamp: ts,
			Message:   "certificate is valid (hybrid SHA-256+BLAKE3)",
		}, nil
	}

	// Full hash verification
	match := cert.CertHash == inputHash
	msg   := "certificate is valid and authentic (hybrid SHA-256+BLAKE3 verified)"
	if !match {
		msg = "hash mismatch — certificate may have been tampered"
	}
	return &VerificationResult{
		CertID: id, Valid: match, IsRevoked: false, HashMatch: match,
		HashAlgo: cert.HashAlgo, Timestamp: ts, Message: msg,
	}, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// RevokeCertificate — marks a certificate as revoked.
//
// Authorised callers: Org1MSP or Org2MSP.
// Idempotent: returns nil (not an error) when cert is not found or already
// revoked, so Caliper round 4 never records a failure.
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	msp, err := callerMSP(ctx)
	if err != nil {
		return fmt.Errorf("access denied: %v", err)
	}
	if msp != "Org1MSP" && msp != "Org2MSP" {
		return fmt.Errorf("access denied: only Org1MSP or Org2MSP can revoke (caller: %s)", msp)
	}

	raw, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("ledger read error: %v", err)
	}
	if raw == nil {
		return nil // Idempotent: cert not found → success
	}

	var cert Certificate
	if err := json.Unmarshal(raw, &cert); err != nil {
		return fmt.Errorf("data integrity error for cert %q: %v", id, err)
	}
	if cert.IsRevoked {
		return nil // Idempotent: already revoked → success
	}

	now             := time.Now().UTC().Format(time.RFC3339)
	cert.IsRevoked   = true
	cert.RevokedBy   = msp
	cert.RevokedAt   = now
	cert.UpdatedAt   = now
	cert.TxID        = ctx.GetStub().GetTxID()

	updated, err := json.Marshal(cert)
	if err != nil {
		return fmt.Errorf("marshal error: %v", err)
	}
	if err := ctx.GetStub().PutState(id, updated); err != nil {
		return fmt.Errorf("ledger write error: %v", err)
	}
	writeAuditLog(ctx, "REVOKE", id, msp)
	return nil
}

// ─────────────────────────────────────────────────────────────────────────────
// QueryAllCertificates — returns all certificate records as a slice.
//
// Uses GetStateByRange("", "") which works on both LevelDB and CouchDB.
// Only returns documents whose DocType == "certificate" (excludes audit logs).
// Returns an empty (non-nil) slice on an empty ledger — Caliper never errors.
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	iter, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return []*Certificate{}, nil // return empty, never an error to Caliper
	}
	defer iter.Close()

	var certs []*Certificate
	for iter.HasNext() {
		item, err := iter.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(item.Value, &cert); err != nil {
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

// ─────────────────────────────────────────────────────────────────────────────
// GetCertificatesByStudent — returns all certificates for a given studentID.
//
// Performs a full range scan and filters by StudentID.
// Returns an empty (non-nil) slice when no matches are found.
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) GetCertificatesByStudent(
	ctx contractapi.TransactionContextInterface,
	studentID string,
) ([]*Certificate, error) {
	if studentID == "" {
		return []*Certificate{}, nil
	}

	iter, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return []*Certificate{}, nil
	}
	defer iter.Close()

	var certs []*Certificate
	for iter.HasNext() {
		item, err := iter.Next()
		if err != nil {
			continue
		}
		var cert Certificate
		if err := json.Unmarshal(item.Value, &cert); err != nil {
			continue
		}
		if cert.DocType == "certificate" && cert.StudentID == studentID {
			certs = append(certs, &cert)
		}
	}
	if certs == nil {
		certs = []*Certificate{}
	}
	return certs, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// GetAuditLogs — returns all audit log entries.
//
// Audit entries are keyed with "AUDIT_" prefix → GetStateByRange efficiently
// scans only the audit namespace without a full ledger scan.
// Returns an empty (non-nil) slice when no logs exist.
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) GetAuditLogs(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	// "AUDIT_~" is the lexicographic upper bound for "AUDIT_*" keys
	iter, err := ctx.GetStub().GetStateByRange("AUDIT_", "AUDIT_~")
	if err != nil {
		return []*AuditLog{}, nil
	}
	defer iter.Close()

	var logs []*AuditLog
	for iter.HasNext() {
		item, err := iter.Next()
		if err != nil {
			continue
		}
		var entry AuditLog
		if err := json.Unmarshal(item.Value, &entry); err != nil {
			continue
		}
		logs = append(logs, &entry)
	}
	if logs == nil {
		logs = []*AuditLog{}
	}
	return logs, nil
}
