'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload Module — BCMS BLAKE3 OPTIMIZED Benchmark
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : IssueCertificate(id, studentID, studentName, degree,
 *                               issuer, issueDate, metadata)
 *  RBAC      : Org1MSP only (invokerIdentity: User1@org1.example.com)
 *  Guarantee : 0 failures — idempotent (duplicate IDs return nil)
 *
 *  BLAKE3 OPTIMIZATION DESIGN:
 *    - Generates a large random metadata payload of 200KB+ per transaction
 *    - The metadata is passed to the chaincode where BLAKE3 hashing is applied:
 *        hash1 = BLAKE3(core fields)
 *        hash2 = BLAKE3(metadata 200KB+)
 *        finalHash = BLAKE3(hash1 || hash2)
 *    - This demonstrates the performance benefits of BLAKE3 over SHA-256
 *      especially on large metadata payloads.
 *
 *  PAYLOAD STRATEGY:
 *    - Base size: 200 * 1024 bytes = 204,800 bytes (~200KB) minimum
 *    - Random content per transaction: prevents caching/deduplication
 *    - Total payload per tx ≈ 200KB+ metadata + cert fields
 *
 *  NOTE: No client-side hash computation — hash is computed ON-CHAIN.
 *        The new chaincode signature is:
 *          IssueCertificate(id, studentID, studentName, degree,
 *                           issuer, issueDate, metadata)
 * ══════════════════════════════════════════════════════════════════════
 */

// ─── Constants ─────────────────────────────────────────────────────────────

/** Minimum metadata payload size in bytes (200KB) */
const METADATA_MIN_BYTES = 200 * 1024; // 204,800 bytes

/** Extra random bytes added per transaction (0-4KB variance for realism) */
const METADATA_VARIANCE_BYTES = 4 * 1024;

/** Alphabet for random string generation (base-64 safe chars) */
const RAND_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

// ─── Helper: Random String Generator ───────────────────────────────────────

/**
 * Generates a cryptographically-random-looking string of exactly `length` bytes.
 * Uses Math.random for speed (we do NOT need security here, only size + variety).
 *
 * @param {number} length - Desired string length in characters (≈ bytes for ASCII)
 * @returns {string}
 */
function generateRandomString(length) {
    // Use a chunked approach to avoid string concatenation overhead
    const chunkSize = 8192;
    const chunks = [];
    let remaining = length;

    while (remaining > 0) {
        const size = Math.min(chunkSize, remaining);
        const chunk = new Array(size);
        for (let i = 0; i < size; i++) {
            // Fast random char selection
            chunk[i] = RAND_CHARS[(Math.random() * RAND_CHARS.length) | 0];
        }
        chunks.push(chunk.join(''));
        remaining -= size;
    }

    return chunks.join('');
}

/**
 * Generates a structured metadata payload that includes:
 *  1. A header with transaction context info (for debuggability)
 *  2. A large random blob that pushes total size to 200KB+
 *
 * The structure is designed to mimic real-world large document metadata
 * (e.g., transcript data, credential attachments, diploma scans in base64).
 *
 * @param {number} workerIdx - Worker index for header context
 * @param {number} txIdx     - Transaction index for header context
 * @returns {string}         - JSON-serializable string ≥ 200KB
 */
function generateLargeMetadataPayload(workerIdx, txIdx) {
    // Header section (fixed, small)
    const header = JSON.stringify({
        source:    'bcms-blake3-optimized-benchmark',
        algorithm: 'BLAKE3',
        worker:    workerIdx,
        txIndex:   txIdx,
        timestamp: Date.now(),
        payloadVersion: '2.0-blake3',
        description: 'Large metadata payload for BLAKE3 performance test. ' +
                     'This payload simulates real-world academic transcript data ' +
                     'embedded as base64-encoded attachments in certificate metadata. ' +
                     'BLAKE3 hashing of this payload demonstrates the architectural ' +
                     'throughput improvements over the SHA-256 baseline.',
    });

    // Calculate how many random bytes we need to reach 200KB+
    const randomBytesNeeded = METADATA_MIN_BYTES
        + Math.floor(Math.random() * METADATA_VARIANCE_BYTES)
        - header.length
        - 64; // reserve space for JSON wrapper

    const randomBlob = generateRandomString(Math.max(1024, randomBytesNeeded));

    // Combine into a single flat string (avoids JSON.stringify on large objects)
    // Format: "HEADER|||RANDOM_BLOB"
    return header + '|||' + randomBlob;
}

// ─── Workload Module ────────────────────────────────────────────────────────

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(
        workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
    ) {
        await super.initializeWorkloadModule(
            workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
        );
        this.txIndex = 0;

        // Pre-log payload size once per worker initialization
        const samplePayload = generateLargeMetadataPayload(workerIndex, 0);
        const sampleSizeKB  = (Buffer.byteLength(samplePayload, 'utf8') / 1024).toFixed(2);
        console.log(
            `[BLAKE3 Optimized] Worker ${workerIndex} initialized. ` +
            `Sample metadata payload size: ${sampleSizeKB} KB`
        );
    }

    async submitTransaction() {
        this.txIndex++;

        const workerIdx   = this.workerIndex || 0;
        const certID      = `CERT_${workerIdx}_${this.txIndex}`;
        const studentID   = `STU_${workerIdx}_${this.txIndex}`;
        const studentName = `Student_${workerIdx}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = new Date().toISOString().split('T')[0];

        // ── Generate 200KB+ metadata payload ──────────────────────────────
        // This is the core of the BLAKE3 performance test.
        // The metadata is sent to the chaincode which applies:
        //   hash2 = BLAKE3(metadata)
        // This exposes the high performance of BLAKE3 on large inputs.
        const metadata = generateLargeMetadataPayload(workerIdx, this.txIndex);

        // ── Build request using new chaincode signature ───────────────────
        // OLD: IssueCertificate(id, studentID, studentName, degree,
        //                       issuer, issueDate, certHash, signature)
        // NEW: IssueCertificate(id, studentID, studentName, degree,
        //                       issuer, issueDate, metadata)
        //
        // certHash is now computed ON-CHAIN (BLAKE3)
        // No client-side hash or signature needed
        const request = {
            contractId:       'basic',
            contractFunction: 'IssueCertificate',
            // Args must match updated Go func signature EXACTLY:
            // (id, studentID, studentName, degree, issuer, issueDate, metadata)
            contractArguments: [
                certID,
                studentID,
                studentName,
                degree,
                issuer,
                issueDate,
                metadata,       // ← 200KB+ payload — BLAKE3 hashed on-chain
            ],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed — idempotent design
        console.log(
            `[BLAKE3 Optimized] Worker ${this.workerIndex || 0} completed ` +
            `${this.txIndex} transactions.`
        );
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
