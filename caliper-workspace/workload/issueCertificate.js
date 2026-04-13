'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload — BCMS Hybrid-Batch Benchmark  (mirage-batch)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: chaincode-bcms/hybrid-batch (deployed as bcms-hybrid)
 *
 *  Function signature (smartcontract_hybrid.go):
 *    IssueCertificate(
 *      id, studentId, studentName, degree, issuer, issueDate,
 *      certHash, blake3Hash, signature, batchId
 *    ) error
 *
 *  MVCC Safety:
 *    - Each worker generates a UNIQUE ID: CERT_{workerIndex}_{txIndex}
 *    - No two workers ever share a key → zero phantom-read conflicts
 *    - Idempotent: duplicate ID returns nil (not error)
 *
 *  Hybrid Crypto (client-side):
 *    certHash   = SHA-256(studentId|studentName|degree|issuer|issueDate)
 *    blake3Hash = simulated BLAKE3 via SHA-256(SHA-256(fields)) as placeholder
 *                 In production, use a real BLAKE3 library (e.g. @noble/hashes)
 *                 For benchmarking purposes this is sufficient — the chaincode
 *                 stores blake3Hash as advisory metadata and does NOT validate it.
 *
 *  Batch Design:
 *    batchId groups certs by worker + round for research paper traceability.
 *    On-chain each cert is still an independent state write (MVCC-safe).
 * ══════════════════════════════════════════════════════════════════════════
 */
class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.batchId   = '';
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        // Freeze issueDate per worker-round so all certs in a batch share the same date
        this.issueDate = new Date().toISOString().split('T')[0];
        // Unique batch ID per worker × round
        this.batchId   = `BATCH_W${workerIndex}_R${roundIndex}_${Date.now()}`;
    }

    async submitTransaction() {
        this.txIndex++;

        const w           = this.workerIndex || 0;
        const certID      = `CERT_${w}_${this.txIndex}`;
        const studentID   = `STU_${w}_${this.txIndex}`;
        const studentName = `Student_${w}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = this.issueDate;

        // ── SHA-256 hash (primary, validated on-chain) ──────────────────
        // Formula: SHA256(studentId|studentName|degree|issuer|issueDate)
        // Must match ComputeHybridHash() in smartcontract_hybrid.go exactly.
        const fields    = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash  = crypto.createHash('sha256').update(fields).digest('hex');

        // ── BLAKE3 advisory hash (stored, NOT validated on-chain) ────────
        // Simulated as double-SHA256 for benchmarking.
        // Replace with real BLAKE3 (e.g. require('@noble/hashes/blake3'))
        // in production deployments.
        const blake3Hash = crypto.createHash('sha256').update(certHash).digest('hex');

        // ── Digital signature placeholder ────────────────────────────────
        const signature  = `SIG_${certID}_${certHash.substring(0, 16)}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',
            // Args MUST match Go func signature order exactly:
            // (id, studentId, studentName, degree, issuer, issueDate,
            //  certHash, blake3Hash, signature, batchId)
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
