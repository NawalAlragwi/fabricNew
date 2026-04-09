'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * \u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557
 *  BatchIssueCertificates Workload Module \u2014 BCMS Benchmark (mirage-batch)
 * \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d
 *
 *  Phase 3: Application-level Batching (Batch Size = 5)
 *
 *  PERFORMANCE GAIN vs Baseline:
 *    - 1 transaction = 5 certificates
 *    - 80% reduction in orderer round-trips
 *    - Effective throughput: TPS x 5 certificates/second
 *
 *  SECURITY GAIN vs Baseline:
 *    - Atomic write: all 5 certs committed together or none
 *    - Prevents partial-write vulnerabilities
 *    - BatchID in audit log = complete traceability
 *
 *  MVCC SAFETY:
 *    Key pattern: BCERT_{workerIndex}_{batchIndex}_{1..5}
 *    Each worker writes to a unique non-overlapping key range.
 *    Zero MVCC conflicts guaranteed.
 *
 *  Chaincode function: BatchIssueCertificates(batchJSON string) *BatchResult
 *  contractArguments: [JSON.stringify([{id, studentID, studentName, degree,
 *                      issuer, issueDate, signature}, ...])]
 */
class BatchIssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.batchIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.batchIndex = 0;
    }

    async submitTransaction() {
        this.batchIndex++;
        const workerIdx  = this.workerIndex || 0;
        const BATCH_SIZE = 5;

        const batch = [];
        for (let i = 1; i <= BATCH_SIZE; i++) {
            const certID      = `BCERT_${workerIdx}_${this.batchIndex}_${i}`;
            const studentID   = `BSTU_${workerIdx}_${this.batchIndex}_${i}`;
            const studentName = `BatchStudent_${workerIdx}_${this.batchIndex}_${i}`;
            const degree      = 'Bachelor of Computer Science';
            const issuer      = 'Digital University';
            const issueDate   = new Date().toISOString().split('T')[0];

            // client-side SHA-256; server overwrites with hybrid sha256-xor-blake3
            const fields    = [studentID, studentName, degree, issuer, issueDate].join('|');
            const certHash  = crypto.createHash('sha256').update(fields).digest('hex');
            const signature = `BSIG_${certID}_${certHash.substring(0, 16)}`;

            batch.push({ id: certID, studentID, studentName, degree, issuer, issueDate, signature });
        }

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'BatchIssueCertificates',
            contractArguments: [JSON.stringify(batch)],  // single JSON arg = batch of 5
            readOnly:          false,
            timeout:           240
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new BatchIssueCertificateWorkload() };
