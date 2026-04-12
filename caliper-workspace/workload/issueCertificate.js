'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const { buildDeterministicMetadata } = require('./metadataUtil');

/** Same calendar day for Issue + Verify rounds (avoids UTC date drift). */
const ISSUE_DATE = '2026-04-13';

/**
 * ══════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload Module — BCMS BLAKE3 Benchmark
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : IssueCertificate(id, studentID, studentName, degree,
 *                               issuer, issueDate, metadata)
 *  Metadata  : Deterministic ~200KB (required so VerifyCertificate can recompute BLAKE3)
 * ══════════════════════════════════════════════════════════════════════
 */
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
        const sample = buildDeterministicMetadata(workerIndex, 1);
        const kb = (Buffer.byteLength(sample, 'utf8') / 1024).toFixed(2);
        console.log(`[IssueCertificate] Worker ${workerIndex}: deterministic metadata ≈ ${kb} KB`);
    }

    async submitTransaction() {
        this.txIndex++;

        const workerIdx   = this.workerIndex || 0;
        const certID      = `CERT_${workerIdx}_${this.txIndex}`;
        const studentID   = `STU_${workerIdx}_${this.txIndex}`;
        const studentName = `Student_${workerIdx}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = ISSUE_DATE;
        const metadata    = buildDeterministicMetadata(workerIdx, this.txIndex);

        const request = {
            contractId:       'basic',
            contractFunction: 'IssueCertificate',
            contractArguments: [
                certID,
                studentID,
                studentName,
                degree,
                issuer,
                issueDate,
                metadata,
            ],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        console.log(`[IssueCertificate] Worker ${this.workerIndex || 0} finished ${this.txIndex} txs.`);
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
