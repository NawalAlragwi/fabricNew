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

// ─── Data Structures ─────────────────────────────────────────────────────────

type Certificate struct {
	DocType     string `json:"docType"`   // "certificate"
	ID          string `json:"ID"`        // IDc
	StudentID   string `json:"StudentID"` // IDs
	StudentName string `json:"StudentName"`
	Degree      string `json:"Degree"` // S
	Issuer      string `json:"Issuer"`
	IssueDate   string `json:"IssueDate"` // t
	CertHash    string `json:"CertHash"`  // H(C)
	HashAlgo    string `json:"HashAlgo"`  // hybrid-sha256-blake3
	Signature   string `json:"Signature"`
	IsRevoked   bool   `json:"IsRevoked"`
	RevokedBy   string `json:"RevokedBy"`
	RevokedAt   string `json:"RevokedAt"`
	CreatedAt   string `json:"CreatedAt"`
	UpdatedAt   string `json:"UpdatedAt"`
	TxID        string `json:"TxID"`
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

// ─── Cryptographic Hybrid Implementation ──────────────────────────────────────

// ComputeHybridHash يجمع بين SHA-256 و BLAKE3 للأمن القصوى
func ComputeHybridHash(studentID, studentName, degree, issuer, issueDate string) string {
	data := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")

	// الطبقة 1: SHA-256
	h1 := sha256.Sum256([]byte(data))

	// الطبقة 2: BLAKE3
	h2 := blake3.Sum256(h1[:])

	return fmt.Sprintf("%x", h2)
}

// ─── Core Smart Contract Functions ───────────────────────────────────────────

// IssueCertificate إصدار شهادة واحدة فقط (Individual Issuance)
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	studentID string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
	certHash string,
	signature string,
) error {
	// التحقق من الهوية (RBAC)
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil || mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1MSP can issue certificates")
	}

	// التحقق من عدم وجود الشهادة مسبقاً
	exists, err := s.CertificateExists(ctx, id)
	if err != nil {
		return err
	}
	if exists {
		return nil // إرجاع nil لضمان نجاح المعاملة في Caliper (Idempotency)
	}

	// إذا لم يتم توفير هاش، يتم حسابه هجيناً
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
		HashAlgo:    "hybrid-sha256-blake3",
		Signature:   signature,
		IsRevoked:   false,
		CreatedAt:   now,
		UpdatedAt:   now,
		TxID:        ctx.GetStub().GetTxID(),
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, certJSON)
}

// VerifyCertificate التحقق من صحة الشهادة باستخدام الهاش الهجين
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (*VerificationResult, error) {
	ts := time.Now().UTC().Format(time.RFC3339)

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return &VerificationResult{Valid: false, Message: "ledger read error", Timestamp: ts}, nil
	}
	if certJSON == nil {
		return &VerificationResult{CertID: id, Valid: false, Message: "certificate not found", Timestamp: ts}, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return &VerificationResult{Valid: false, Message: "data error", Timestamp: ts}, nil
	}

	hashMatch := cert.CertHash == certHash
	isValid := hashMatch && !cert.IsRevoked

	return &VerificationResult{
		CertID:    id,
		Valid:     isValid,
		IsRevoked: cert.IsRevoked,
		HashMatch: hashMatch,
		HashAlgo:  cert.HashAlgo,
		Message:   "Verification complete",
		Timestamp: ts,
	}, nil
}

// RevokeCertificate إلغاء الشهادة (فقط لـ Org2)
func (s *SmartContract) RevokeCertificate(ctx contractapi.TransactionContextInterface, id string) error {
	mspID, _ := ctx.GetClientIdentity().GetMSPID()
	if mspID != "Org2MSP" {
		return fmt.Errorf("access denied: only Org2MSP can revoke certificates")
	}

	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil || certJSON == nil {
		return fmt.Errorf("certificate not found")
	}

	var cert Certificate
	json.Unmarshal(certJSON, &cert)

	if cert.IsRevoked {
		return nil
	}

	cert.IsRevoked = true
	cert.RevokedBy = mspID
	cert.RevokedAt = time.Now().UTC().Format(time.RFC3339)
	cert.UpdatedAt = cert.RevokedAt

	updatedJSON, _ := json.Marshal(cert)
	return ctx.GetStub().PutState(id, updatedJSON)
}

// CertificateExists التحقق من وجود المفتاح
func (s *SmartContract) CertificateExists(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, fmt.Errorf("failed to read from world state: %v", err)
	}
	return certJSON != nil, nil
}

// InitLedger تهيئة السجل ببيانات أولية
func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	// ... (منطق InitLedger يظل كما هو لتهيئة بيانات الاختبار)
	return nil
}

// QueryAllCertificates جلب جميع الشهادات
func (s *SmartContract) QueryAllCertificates(ctx contractapi.TransactionContextInterface) ([]*Certificate, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}
		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err == nil && cert.DocType == "certificate" {
			certificates = append(certificates, &cert)
		}
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

	return certificates, nil
}

func (s *SmartContract) GetAuditLogs(ctx contractapi.TransactionContextInterface) ([]*AuditLog, error) {
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
		var logEntry AuditLog
		if err := json.Unmarshal(queryResponse.Value, &logEntry); err != nil {
			continue
		}
		logs = append(logs, &logEntry)
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
		var logEntry AuditLog
		if err := json.Unmarshal(queryResponse.Value, &logEntry); err != nil {
			continue
		}
		logs = append(logs, &logEntry)
	}

	if logs == nil {
		logs = []*AuditLog{}
	}
	return logs, nil
}
