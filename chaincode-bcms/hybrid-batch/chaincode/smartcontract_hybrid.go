package chaincode

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
	"lukechampine.com/blake3" // استخدام BLAKE3 للسرعة القصوى في الدمج
)

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

type VerificationResult struct {
	CertID    string `json:"certID"`
	Valid     bool   `json:"valid"`
	IsRevoked bool   `json:"isRevoked"`
	HashMatch bool   `json:"hashMatch"`
	HashAlgo  string `json:"hashAlgo"`
	Message   string `json:"message"`
	Timestamp string `json:"timestamp"`
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

// SmartContract — main contract for hybrid-batch
type SmartContract struct {
	contractapi.Contract
}

// ─── Cryptographic Hybrid Implementation ──────────────────────────────────────

// ComputeHybridHash يمثل "القفل المزدوج" (Double-Lock)
// يجمع بين SHA-256 للمعيارية و BLAKE3 للحصانة ضد تمديد الطول والسرعة
func ComputeHybridHash(studentID, studentName, degree, issuer, issueDate string) string {
	data := strings.Join([]string{studentID, studentName, degree, issuer, issueDate}, "|")
	
	// الطبقة 1: SHA-256
	h1 := sha256.Sum256([]byte(data))
	
	// الطبقة 2: BLAKE3 (تأخذ مخرج SHA كمدخل لها)
	h2 := blake3.Sum256(h1[:])
	
	return fmt.Sprintf("%x", h2)
}

// ─── Optimized Batch Functions ──────────────────────────────────────────────

// IssueCertificateBatch هي المساهمة الجوهرية لتحسين الأداء
// تسمح بمعالجة مئات الشهادات في معاملة بلوكشين واحدة
func (s *SmartContract) IssueCertificateBatch(
	ctx contractapi.TransactionContextInterface,
	certsJSON string,
) error {
	// التحقق من الهوية (RBAC)
	mspID, _ := ctx.GetClientIdentity().GetMSPID()
	if mspID != "Org1MSP" {
		return fmt.Errorf("unauthorized: only Org1 can issue batches")
	}

	var certs []Certificate
	if err := json.Unmarshal([]byte(certsJSON), &certs); err != nil {
		return fmt.Errorf("failed to parse batch: %v", err)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	txID := ctx.GetStub().GetTxID()

	for _, cert := range certs {
		// تطبيق الهاش الهجين تلقائياً لكل شهادة في الدفعة
		cert.CertHash = ComputeHybridHash(cert.StudentID, cert.StudentName, cert.Degree, cert.Issuer, cert.IssueDate)
		cert.HashAlgo = "hybrid-sha256-blake3"
		cert.DocType = "certificate"
		cert.CreatedAt = now
		cert.UpdatedAt = now
		cert.TxID = txID

		certJSON, _ := json.Marshal(cert)
		// تخزين كل شهادة بمفتاحها الخاص للبحث السريع لاحقاً
		if err := ctx.GetStub().PutState(cert.ID, certJSON); err != nil {
			return fmt.Errorf("failed to write cert %s: %v", cert.ID, err)
		}
	}

	return nil
}

// ─── Enhanced Verification ──────────────────────────────────────────────────

func (s *SmartContract) VerifyCertificateHybrid(
	ctx contractapi.TransactionContextInterface,
	id string,
	inputHash string,
) (*VerificationResult, error) {
	certBytes, _ := ctx.GetStub().GetState(id)
	if certBytes == nil {
		return &VerificationResult{Valid: false, Message: "Not Found"}, nil
	}

	var cert Certificate
	json.Unmarshal(certBytes, &cert)

	// التحقق من الهاش الهجين
	hashMatch := cert.CertHash == inputHash
	
	return &VerificationResult{
		CertID:    id,
		Valid:     hashMatch && !cert.IsRevoked,
		HashMatch: hashMatch,
		IsRevoked: cert.IsRevoked,
		HashAlgo:  cert.HashAlgo,
		Message:   "Verified via Hybrid SHA256+BLAKE3",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}, nil
}

func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
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
		hash := ComputeHybridHash(seed.studentID, seed.studentName, seed.degree, seed.issuer, seed.issueDate)
		cert := Certificate{
			DocType:     "certificate",
			ID:          seed.id,
			StudentID:   seed.studentID,
			StudentName: seed.studentName,
			Degree:      seed.degree,
			Issuer:      seed.issuer,
			IssueDate:   seed.issueDate,
			CertHash:    hash,
			HashAlgo:    "hybrid-sha256-blake3",
			Signature:   fmt.Sprintf("SIG_%s_%s", seed.id, hash[:16]),
			IsRevoked:   false,
			CreatedAt:   time.Now().UTC().Format(time.RFC3339),
			UpdatedAt:   time.Now().UTC().Format(time.RFC3339),
			TxID:        ctx.GetStub().GetTxID(),
		}

		certBytes, err := json.Marshal(cert)
		if err != nil {
			return fmt.Errorf("failed to marshal certificate %s: %v", seed.id, err)
		}

		if err := ctx.GetStub().PutState(seed.id, certBytes); err != nil {
			return fmt.Errorf("failed to put certificate %s: %v", seed.id, err)
		}
	}

	return nil
}
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
        mspID, err := ctx.GetClientIdentity().GetMSPID()
        if err != nil {
                return fmt.Errorf("access denied: failed to read MSP: %v", err)
        }
        if mspID != "Org1MSP" {
                return fmt.Errorf("access denied: only Org1MSP can issue certificates")
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

        computedHash := ComputeHybridHash(studentID, studentName, degree, issuer, issueDate)
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
                HashAlgo:    "hybrid-sha256-blake3",
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

func (s *SmartContract) VerifyCertificate(
        ctx contractapi.TransactionContextInterface,
        id string,
        certHash string,
) (*VerificationResult, error) {
        ts := time.Now().UTC().Format(time.RFC3339)

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
                        IsRevoked: false,
                        HashMatch: false,
                        HashAlgo:  cert.HashAlgo,
                        Message:   "hash mismatch",
                        Timestamp: ts,
                }, nil
        }

        return &VerificationResult{
                CertID:    id,
                Valid:     true,
                IsRevoked: false,
                HashMatch: true,
                HashAlgo:  cert.HashAlgo,
                Message:   "certificate is valid and authentic",
                Timestamp: ts,
        }, nil
}

func (s *SmartContract) RevokeCertificate(
        ctx contractapi.TransactionContextInterface,
        id string,
) error {
        mspID, err := ctx.GetClientIdentity().GetMSPID()
        if err != nil {
                return fmt.Errorf("access denied: failed to read MSP: %v", err)
        }
        if mspID != "Org2MSP" {
                return fmt.Errorf("access denied: only Org2MSP can revoke certificates")
        }

        certJSON, err := ctx.GetStub().GetState(id)
        if err != nil {
                return fmt.Errorf("failed to read certificate: %v", err)
        }
        if certJSON == nil {
                return fmt.Errorf("certificate not found")
        }

        var cert Certificate
        if err := json.Unmarshal(certJSON, &cert); err != nil {
                return fmt.Errorf("failed to unmarshal certificate: %v", err)
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

        return certificates, nil
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