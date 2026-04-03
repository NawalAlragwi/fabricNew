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
