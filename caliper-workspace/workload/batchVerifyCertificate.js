'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * \u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557
 *  BatchVerifyCertificates Workload Module \u2014 BCMS Benchmark (mirage-batch)
 * \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d
 *
 *  Phase 3: Application-level Batching (Batch Size = 5)
 *
 *  PERFORMANCE GAIN vs Baseline:
 *    - 1 query = 5 certificate verifications
 *    - 5x reduction in client-peer round-trips
 *    - readOnly:true \u2014 direct peer query, bypasses orderer entirely
 *
 *  SECURITY GAIN vs Baseline:
 *    - Simultaneous batch verification eliminates Man-in-the-Middle window
 *      that exists between sequential individual verification calls
 *
 *  Chaincode function: BatchVerifyCertificates(requestsJSON) []*VerificationResult
 *  contractArguments: [JSON.stringify([{id, certHash}, ...])]
 */
class BatchVerifyCertificateWorkload extends WorkloadModuleBase {
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

        const requests = [];
        for (let i = 1; i <= BATCH_SIZE; i++) {
            const certID      = `BCERT_${workerIdx}_${this.batchIndex}_${i}`;
            const studentID   = `BSTU_${workerIdx}_${this.batchIndex}_${i}`;
            const studentName = `BatchStudent_${workerIdx}_${this.batchIndex}_${i}`;
            const degree      = 'Bachelor of Computer Science';
            const issuer      = 'Digital University';
            const issueDate   = new Date().toISOString().split('T')[0];

            const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
            const certHash = crypto.createHash('sha256').update(fields).digest('hex');

            requests.push({ id: certID, certHash });
        }

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'BatchVerifyCertificates',
            contractArguments: [JSON.stringify(requests)],  // single JSON arg = batch of 5
            readOnly:          true,    // direct peer query \u2014 max throughput
            timeout:           240
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new BatchVerifyCertificateWorkload() };
