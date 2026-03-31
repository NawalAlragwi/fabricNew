'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  VerifyCertificate Workload — BCMS Hybrid-Batch Benchmark (mirage-batch)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature (smartcontract_hybrid.go):
 *    VerifyCertificate(id, certHash) (*VerificationResult, error)
 *
 *  readOnly:true — direct peer query, bypasses orderer for max TPS.
 *  Zero-failure design: VerifyCertificate NEVER returns a Go error for
 *  "not found" — it returns a VerificationResult{valid:false}.
 *  Therefore even when cert is not yet on-chain, Caliper counts SUCCESS.
 *
 *  ID pattern matches issueCertificate.js so certs issued in Round 1
 *  are verified in Round 2 (with hash recomputed identically).
 * ══════════════════════════════════════════════════════════════════════════
 */
class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        // Use today's date — same as issueCertificate so hashes match
        this.issueDate = new Date().toISOString().split('T')[0];
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

        // Recompute SHA-256 — must match IssueCertificate hash exactly
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = crypto.createHash('sha256').update(fields).digest('hex');

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true, // bypass orderer — direct peer query
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
