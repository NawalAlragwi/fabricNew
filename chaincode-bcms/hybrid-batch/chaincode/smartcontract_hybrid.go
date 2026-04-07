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
var hasherPool = sync.Pool{
	New: func() interface{} { return blake3.New(32, nil) },
}

// ─── Data Structures ─────────────────────────────────────────────────────────

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

type AuditLog struct {
	DocType   string `json:"docType"`
	TxID      string `json:"TxID"`
	Function  string `json:"Function"`
	CertID    string `json:"CertID"`
	CallerMSP string `json:"CallerMSP"`
	Result    string `json:"Result"`
	Timestamp string `json:"Timestamp"`
}

type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	HashAlgo  string `json:"hashAlgo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
}

type SmartContract struct {
	contractapi.Contract
}

// ─── Hybrid Hash: SHA-256 XOR BLAKE3 ─────────────────────────────────────────
//
// كل خوارزمية تعمل على البيانات الأصلية بشكل مستقل
// ثم يتم XOR الناتجَين للحصول على hash مدمج 256-bit
//
// المزايا:
//   - أقوى من كل خوارزمية منفردة (يحتاج المهاجم كسر كليهما)
//   - SHA-256: معيار NIST موثّق
//   - BLAKE3: أسرع بـ 3-10x مع SIMD
//   - XOR: يحافظ على طول 256-bit بدون collision إضافية

func ComputeHybridHash(studentID, studentName, degree, issuer, issueDate string) string {
	// بناء البيانات المُدخلة
	data := strings.Join(
		[]string{studentID, studentName, degree, issuer, issueDate}, "|",
	)
	dataBytes := []byte(data)

	// SHA-256 على البيانات الأصلية
	h1 := sha256.Sum256(dataBytes)

	// BLAKE3 على نفس البيانات الأصلية (وليس على ناتج SHA-256)
	h := hasherPool.Get().(*blake3.Hasher)
	h.Reset()
	h.Write(dataBytes)
	var h2 [32]byte
	copy(h2[:], h.Sum(nil))
	hasherPool.Put(h)

	// XOR الناتجَين — كل بايت من SHA-256 مع نظيره من BLAKE3
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
			CreatedAt:   time.Now().UTC().Format(time.RFC3339),
			UpdatedAt:   time.Now().UTC().Format(time.RFC3339),
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

	// Idempotent — لا تُصدر نفس الشهادة مرتين
	existing, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read ledger: %v", err)
	}
	if existing != nil {
		return nil
	}

	// احسب الـ hash إذا لم يُرسل
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

func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	mspID, err := getCallerMSP(ctx)
	if err != nil {
		return fmt.Errorf("access denied: %v", err)
	}
	// ✅ إصلاح: كلا المنظمتين يمكنهما الإلغاء
	if mspID != "Org1MSP" && mspID != "Org2MSP" {
		return fmt.Errorf("access denied: unauthorized organization %s", mspID)
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return fmt.Errorf("failed to read certificate: %v", err)
	}
	// Idempotent — لا خطأ إذا لم توجد الشهادة
	if certJSON == nil {
		return nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return fmt.Errorf("failed to unmarshal certificate: %v", err)
	}
	// Idempotent — لا خطأ إذا سبق إلغاؤها
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

func (s *SmartContract) QueryAllCertificates(
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

func (s *SmartContract) GetCertificatesByStudent(
	ctx contractapi.TransactionContextInterface,
	studentID string,
) ([]*Certificate, error) {
	if studentID == "" {
		return []*Certificate{}, nil
	}

	queryString := fmt.Sprintf(
		`{"selector":{"docType":"certificate","StudentID":"%s"}}`,
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

func (s *SmartContract) GetAuditLogs(
	ctx contractapi.TransactionContextInterface,
) ([]*AuditLog, error) {
	// Range scan أسرع من CouchDB rich query للـ audit logs
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
	studentID, studentName, degree, issuer, issueDate string,
) (string, error) {
	if studentID == "" || studentName == "" || degree == "" ||
		issuer == "" || issueDate == "" {
		return "", fmt.Errorf("all fields are required")
	}
	return ComputeHybridHash(studentID, studentName, degree, issuer, issueDate), nil
}

func (s *SmartContract) GetHashAlgorithm(
	ctx contractapi.TransactionContextInterface,
) (string, error) {
	return "sha256-xor-blake3", nil
}
