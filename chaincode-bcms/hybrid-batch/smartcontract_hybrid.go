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
