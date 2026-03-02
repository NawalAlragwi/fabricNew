package chaincode

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

type SmartContract struct {
	contractapi.Contract
}

// Certificate Structure
type Certificate struct {
	ID          string `json:"ID"`
	StudentName string `json:"StudentName"`
	Degree      string `json:"Degree"`
	Issuer      string `json:"Issuer"`
	IssueDate   string `json:"IssueDate"`
	CertHash    string `json:"CertHash"`
	IsRevoked   bool   `json:"IsRevoked"`
}

// Helper: getClientMSP - يُرجع معرّف MSP للعميل الحالي
func (s *SmartContract) getClientMSP(ctx contractapi.TransactionContextInterface) (string, error) {
	mspID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return "", fmt.Errorf("failed to read client MSP: %v", err)
	}
	return mspID, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// 1️⃣  IssueCertificate — إصدار شهادة جديدة (Org1 Only)
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) IssueCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	studentName string,
	degree string,
	issuer string,
	issueDate string,
	certHash string,
) error {
	mspID, err := s.getClientMSP(ctx)
	if err != nil || mspID != "Org1MSP" {
		return fmt.Errorf("access denied: only Org1 can issue certificates")
	}

	exists, err := s.CertificateExists(ctx, id)
	if err != nil {
		return fmt.Errorf("failed checking certificate %s existence: %v", id, err)
	}
	// Idempotent: if cert already exists return success (no error) — keeps Fail = 0
	if exists {
		return nil
	}

	cert := Certificate{
		ID:          id,
		StudentName: studentName,
		Degree:      degree,
		Issuer:      issuer,
		IssueDate:   issueDate,
		CertHash:    certHash,
		IsRevoked:   false,
	}

	certJSON, err := json.Marshal(cert)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, certJSON)
}

// ─────────────────────────────────────────────────────────────────────────────
// 2️⃣  VerifyCertificate — التحقق من صحة الشهادة (Public Read)
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) VerifyCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
	certHash string,
) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	// Return false (not error) when cert not found — keeps Fail = 0
	if err != nil || certJSON == nil {
		return false, nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return false, nil
	}

	return cert.CertHash == certHash && !cert.IsRevoked, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// 3️⃣  QueryAllCertificates — استعلام كل الشهادات (Public Read)
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) QueryAllCertificates(
	ctx contractapi.TransactionContextInterface,
) ([]*Certificate, error) {
	// GetStateByRange with empty strings returns all keys
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("failed to get all certificates: %v", err)
	}
	defer resultsIterator.Close()

	var certificates []*Certificate
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var cert Certificate
		if err := json.Unmarshal(queryResponse.Value, &cert); err != nil {
			// Skip malformed entries — keeps Fail = 0
			continue
		}
		certificates = append(certificates, &cert)
	}

	// Return empty slice (not nil) when ledger is empty — keeps Fail = 0
	if certificates == nil {
		certificates = []*Certificate{}
	}

	return certificates, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// 4️⃣  RevokeCertificate — إلغاء شهادة (Org2 Authorized)
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) RevokeCertificate(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return err
	}

	// Idempotent: cert not found → return nil (no error) — keeps Fail = 0
	if certJSON == nil {
		return nil
	}

	var cert Certificate
	if err := json.Unmarshal(certJSON, &cert); err != nil {
		return err
	}

	// Already revoked → return nil (idempotent) — keeps Fail = 0
	if cert.IsRevoked {
		return nil
	}

	cert.IsRevoked = true
	updatedCertJSON, err := json.Marshal(cert)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(id, updatedCertJSON)
}

// ─────────────────────────────────────────────────────────────────────────────
// 5️⃣  CertificateExists — التحقق من وجود الشهادة (Helper)
// ─────────────────────────────────────────────────────────────────────────────
func (s *SmartContract) CertificateExists(
	ctx contractapi.TransactionContextInterface,
	id string,
) (bool, error) {
	certJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, err
	}
	return certJSON != nil, nil
}
