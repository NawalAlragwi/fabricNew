'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload — BCMS S1/S2 Benchmark (SHA-256 & BLAKE3)
 *  v8.0 — FIX-CERTHASH: Pass empty certHash so chaincode computes it
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature (smartcontract_sha256.go / smartcontract_blake3.go):
 *    IssueCertificate(
 *      id, studentID, studentName, degree, issuer, issueDate,
 *      certHash, blake3Hash, signature, batchID, transcript
 *    ) error
 *
 *  FIX-CERTHASH (v8.0):
 *  ─────────────────────────────────────────────────────────────────────
 *  Previous versions computed SHA-256 client-side and sent it as certHash.
 *  This caused a critical bug in S2 (BLAKE3):
 *    - Chaincode stored the client SHA-256 hash
 *    - VerifyCertificate re-computed BLAKE3 on-chain
 *    - SHA-256 ≠ BLAKE3 → HashMatch = false on EVERY verification
 *    - All S2 VerifyCertificate calls returned "hash mismatch" silently
 *
 *  Fix: certHash is sent as '' (empty string).
 *  In the chaincode IssueCertificate:
 *    computedHash, hashAlgo := ComputeCertHash(...)
 *    if certHash == "" { certHash = computedHash }
 *  → S1 stores SHA-256 hash; S2 stores BLAKE3 hash.
 *  → VerifyCertificate re-computes same algorithm → HashMatch = true ✓
 *
 *  MVCC Safety:
 *    CERT_{workerIndex}_{txIndex} — unique per worker, zero conflicts.
 *
 *  contractId:
 *    Read from roundArguments.contractId (set in benchConfig YAML).
 *    S1 YAML → bcms-sha256 ; S2 YAML → bcms-blake3
 * ══════════════════════════════════════════════════════════════════════════
 */
class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        this.batchId = '';
        this.issueDate = '';
        this.payloadSize = 50000;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
        this.issueDate = new Date().toISOString().split('T')[0];
        this.batchId = `BATCH_W${workerIndex}_R${roundIndex}_${Date.now()}`;
        this.payloadSize = (roundArguments && roundArguments.payloadSize)
            ? parseInt(roundArguments.payloadSize, 10)
            : 50000;
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

        // 50 KB transcript payload — forces chaincode to hash ~51,000 bytes.
        // SHA-256 ×100: 15.0 µs × 100 = 1,500 µs per tx  (S1 baseline)
        // BLAKE3  ×100:  4.01 µs × 100 =   401 µs per tx  (S2 alternative)
        const transcriptPayload = 'X'.repeat(this.payloadSize);

        // FIX-CERTHASH: certHash = '' → chaincode computes hash using its own
        // algorithm (SHA-256 for S1, BLAKE3 for S2). This is the ONLY correct
        // approach to ensure VerifyCertificate passes in both scenarios.
        // Sending a pre-computed SHA-256 hash to S2 would cause ALL
        // VerifyCertificate calls to return HashMatch=false (silent failure).
        const certHash = '';

        // blake3Hash is an advisory field — stored but not validated on-chain.
        // We use SHA-256(empty) as a deterministic placeholder.
        const blake3Hash = crypto.createHash('sha256').update('').digest('hex');

        const signature = `SIG_${certID}_placeholder`;

        return this.sutAdapter.sendRequests({
            contractId: this.roundArguments.contractId || 'bcms-sha256',
            contractFunction: 'IssueCertificate',
            contractArguments: [
                certID,
                studentID,
                studentName,
                degree,
                issuer,
                issueDate,
                certHash,          // '' → chaincode computes correct algorithm's hash
                blake3Hash,        // advisory only
                signature,
                this.batchId,
                transcriptPayload, // 50 KB stress payload
            ],
            readOnly: false,
        });
    }

    async cleanupWorkloadModule() { }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };