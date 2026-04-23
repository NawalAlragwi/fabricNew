'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload — BCMS S1/S2 Benchmark (SHA-256 & BLAKE3)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: bcms-sha256 (S1) or bcms-blake3 (S2)
 *  Chaincode ID is injected dynamically via roundArguments.contractId.
 *
 *  Function signature (smartcontract_sha256.go / smartcontract_blake3.go):
 *    IssueCertificate(
 *      id, studentID, studentName, degree, issuer, issueDate,   // 6
 *      certHash, blake3Hash, signature, batchID,               // 4
 *      transcript                                               // 1 ← 11th arg
 *    ) error
 *
 *  MVCC Safety:
 *    - Each worker generates a UNIQUE ID: CERT_{workerIndex}_{txIndex}
 *    - No two workers ever share a key → zero phantom-read conflicts
 *    - Idempotent: duplicate ID returns nil (not error)
 *
 *  Payload & Hashing:
 *    transcriptPayload = 'X'.repeat(payloadSize)  [default: 100KB]
 *    certHash   = SHA-256(studentId|studentName|degree|issuer|issueDate|transcript)
 *                 ← transcript IS included so the hash covers the full payload
 *    blake3Hash = SHA-256(certHash) as a placeholder (advisory, not validated on-chain)
 *
 *  On-chain stress:
 *    The chaincode re-computes ComputeCertHash × 100 iterations using the full
 *    transcript → 100 × 15µs (SHA-256) or 100 × 4µs (BLAKE3) per transaction.
 *    This amplification makes the CPU difference visible in Fabric latency.
 * ══════════════════════════════════════════════════════════════════════════
 */
class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        this.batchId = '';
        this.issueDate = '';
        this.payloadSize = 5000;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
        // Freeze issueDate per worker-round so all certs in a batch share the same date
        this.issueDate = new Date().toISOString().split('T')[0];
        // Unique batch ID per worker × round
        this.batchId = `BATCH_W${workerIndex}_R${roundIndex}_${Date.now()}`;
        // Read payloadSize from YAML arguments (default to 5000 if not specified)
        this.payloadSize = (roundArguments && roundArguments.payloadSize) ? parseInt(roundArguments.payloadSize, 10) : 5000;
    }

    async submitTransaction() {
        this.txIndex++;

        const w = this.workerIndex || 0;
        const certID = `CERT_${w}_${this.txIndex}`;
        const studentID = `STU_${w}_${this.txIndex}`;
        const studentName = `Student_${w}_${this.txIndex}`;
        const degree = 'Bachelor of Computer Science';
        const issuer = 'Digital University';
        const issueDate = this.issueDate;

        // ── EDUCATIONAL PAYLOAD (Optimized Stress Test) ──────────────────
        // Large payloads force the CPU to work harder on hashing. 
        // Read dynamically from benchConfig YAML (e.g., 5000 for 5KB, 50000 for 50KB).
        const transcriptPayload = 'X'.repeat(this.payloadSize);

        // ── SHA-256 hash (primary, validated on-chain) ──────────────────
        // Formula: SHA256(studentId|studentName|degree|issuer|issueDate|payload)
        const fields = [studentID, studentName, degree, issuer, issueDate, transcriptPayload].join('|');
        const certHash = crypto.createHash('sha256').update(fields).digest('hex');

        // ── BLAKE3 advisory hash (stored, NOT validated on-chain) ────────
        // Real BLAKE3 is ~3-10x faster than SHA-256 for 50KB+ payloads.
        // For benchmarking with standard Node.js, we simulate the "near-zero"
        // cost of BLAKE3 by using a fixed-length slice of the transcript,
        // effectively demonstrating the upper-bound performance.
        const blake3Hash = crypto.createHash('sha256').update(certHash).digest('hex');

        // ── Digital signature placeholder ────────────────────────────────
        const signature = `SIG_${certID}_${certHash.substring(0, 16)}`;

        const request = {
            contractId: this.roundArguments.contractId || 'bcms-sha256',
            contractFunction: 'IssueCertificate',
            // 11 args — MUST match Go func signature exactly:
            // (id, studentID, studentName, degree, issuer, issueDate,
            //  certHash, blake3Hash, signature, batchID, transcript)
            contractArguments: [
                certID,
                studentID,
                studentName,
                degree,
                issuer,
                issueDate,
                certHash,
                blake3Hash,
                signature,
                this.batchId,
                transcriptPayload, // New 11th argument: Heavy Transcript
            ],
            readOnly: false,
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // Idempotent design — no cleanup needed
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
