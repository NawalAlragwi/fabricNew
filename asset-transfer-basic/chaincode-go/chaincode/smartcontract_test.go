package chaincode_test

import (
	"testing"

	"github.com/hyperledger/fabric-samples/asset-transfer-basic/chaincode-go/chaincode"
	"github.com/stretchr/testify/require"
)

// ─── Unit Tests for BCMS SHA-256 Baseline Chaincode ─────────────────────────

// TestComputeCertHash verifies the Double SHA-256 hash computation:
//
//	hash1     = SHA256(studentID|studentName|degree|issuer|issueDate)
//	hash2     = SHA256(metadata)
//	finalHash = SHA256(hash1_bytes || hash2_bytes)
func TestComputeCertHash(t *testing.T) {
	// Test 1: Deterministic output — same inputs must produce same hash
	hash1 := chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "metadata")
	hash2 := chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "metadata")
	require.Equal(t, hash1, hash2, "Double SHA-256 must be deterministic")

	// Test 2: Different metadata must produce different hashes (avalanche effect)
	hashA := chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "payload_A")
	hashB := chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "payload_B")
	require.NotEqual(t, hashA, hashB, "Different metadata must yield different hashes")

	// Test 3: Empty metadata must differ from non-empty metadata
	hashEmpty := chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "")
	hashNonEmpty := chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "data")
	require.NotEqual(t, hashEmpty, hashNonEmpty, "Empty vs non-empty metadata must differ")

	// Test 4: Output must be 64 hex chars (SHA-256 = 32 bytes = 64 hex chars)
	require.Equal(t, 64, len(hash1), "SHA-256 hash must be 64 hex characters")

	// Test 5: Large payload (200KB) — verify no panic and consistent output
	largePayload := make([]byte, 200*1024) // 200KB
	for i := range largePayload {
		largePayload[i] = byte(i % 256)
	}
	hashLarge1 := chaincode.ComputeCertHash("STU999", "Bob", "MSc", "Tech", "2024-06-01", string(largePayload))
	hashLarge2 := chaincode.ComputeCertHash("STU999", "Bob", "MSc", "Tech", "2024-06-01", string(largePayload))
	require.Equal(t, hashLarge1, hashLarge2, "Large payload hash must be deterministic")
	require.Equal(t, 64, len(hashLarge1), "Large payload hash must still be 64 hex chars")
}

// TestComputeCertHashFieldSensitivity verifies that changing each individual
// field produces a different final hash (full avalanche coverage).
func TestComputeCertHashFieldSensitivity(t *testing.T) {
	base := chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "meta")

	// Changing any single field must change the hash
	require.NotEqual(t, base,
		chaincode.ComputeCertHash("STU002", "Alice", "BSc", "Uni", "2024-01-01", "meta"),
		"studentID change must affect hash")
	require.NotEqual(t, base,
		chaincode.ComputeCertHash("STU001", "Bob", "BSc", "Uni", "2024-01-01", "meta"),
		"studentName change must affect hash")
	require.NotEqual(t, base,
		chaincode.ComputeCertHash("STU001", "Alice", "MSc", "Uni", "2024-01-01", "meta"),
		"degree change must affect hash")
	require.NotEqual(t, base,
		chaincode.ComputeCertHash("STU001", "Alice", "BSc", "MIT", "2024-01-01", "meta"),
		"issuer change must affect hash")
	require.NotEqual(t, base,
		chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-02-01", "meta"),
		"issueDate change must affect hash")
	require.NotEqual(t, base,
		chaincode.ComputeCertHash("STU001", "Alice", "BSc", "Uni", "2024-01-01", "META"),
		"metadata case change must affect hash")
}

// TestDoubleHashingDistinctInputs verifies that distinct inputs always yield
// distinct outputs (no trivial collision for test vectors).
func TestDoubleHashingDistinctInputs(t *testing.T) {
	h1 := chaincode.ComputeCertHash("A", "B", "C", "D", "E", "meta_F")
	h2 := chaincode.ComputeCertHash("A", "B", "C", "D", "E", "meta_G") // only metadata differs

	require.Len(t, h1, 64, "hash must be 64 hex chars")
	require.Len(t, h2, 64, "hash must be 64 hex chars")
	require.NotEqual(t, h1, h2, "different metadata must produce different hashes")
}

// TestComputeCertHashMetadataIsolation verifies that the metadata hash
// is isolated from the fields hash (changing metadata only affects hash2,
// but the combined final hash still changes — confirming binding).
func TestComputeCertHashMetadataIsolation(t *testing.T) {
	// Same fields, varying metadata sizes
	hashSmall := chaincode.ComputeCertHash("S", "N", "D", "I", "2024-01-01", "x")
	hashMedium := chaincode.ComputeCertHash("S", "N", "D", "I", "2024-01-01", "x"+string(make([]byte, 1024)))
	hashLarge := chaincode.ComputeCertHash("S", "N", "D", "I", "2024-01-01", "x"+string(make([]byte, 200*1024)))

	// All three must differ despite same core fields
	require.NotEqual(t, hashSmall, hashMedium)
	require.NotEqual(t, hashMedium, hashLarge)
	require.NotEqual(t, hashSmall, hashLarge)

	// All must be valid SHA-256 hex strings
	require.Len(t, hashSmall, 64)
	require.Len(t, hashMedium, 64)
	require.Len(t, hashLarge, 64)
}
