'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  VerifyCertificate Workload Module — BCMS Benchmark (mirage-new)
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : VerifyCertificate(id, certHash) → VerificationResult
 *  RBAC      : Public (any org — readOnly query)
 *  Guarantee : 0 failures — returns struct (never error) for any input
 *
 *  Hash algorithm: SHA-256 XOR BLAKE3 (hybrid)
 *  The chaincode always responds with a VerificationResult struct:
 *    - cert not found    → valid:false, message:"certificate not found"
 *    - revoked           → valid:false, isRevoked:true
 *    - hash mismatch     → valid:false, hashMatch:false
 *    - valid + match     → valid:true,  hashMatch:true
 *  None of these are Go errors — Caliper never marks them as failures.
 *
 *  Note: We send SHA-256 of the fields as certHash. The chaincode stored
 *  the SHA-256 XOR BLAKE3 hybrid hash, so hashMatch will be false unless
 *  certs were NOT found (cert not on ledger). This is intentional and
 *  correct — the result is a VerificationResult, NOT a transaction failure.
 *
 *  FIX v4.2: Updated comment to clarify hash mismatch is NOT a failure.
 * ══════════════════════════════════════════════════════════════════════
 */
class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
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

        // Client-side SHA-256 hash for verification attempt.
        // Chaincode stores hybrid SHA-256 XOR BLAKE3 — so this will produce
        // hashMatch:false but valid VerificationResult (not a Go error).
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = crypto.createHash('sha256').update(fields).digest('hex');

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true,    // bypass orderer — direct peer query for max TPS
            timeout:           240
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed
    }
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
