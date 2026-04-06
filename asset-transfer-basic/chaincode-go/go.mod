module github.com/NawalAlragwi/fabricNew/chaincode-bcms/blake3

go 1.21

require (
	github.com/hyperledger/fabric-contract-api-go/v2 v2.0.0
	lukechampine.com/blake3 v1.3.0
)

// ❌ أزلنا: github.com/zeebo/blake3 — pure Go, no SIMD
// ✅ استخدمنا: lukechampine.com/blake3 — AVX2/SSE4 accelerated
