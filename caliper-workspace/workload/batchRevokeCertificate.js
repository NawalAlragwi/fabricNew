'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * \u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557
 *  BatchRevokeCertificates Workload Module \u2014 BCMS Benchmark (mirage-batch)
 * \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d
 *
 *  Phase 3: Application-level Batching (Batch Size = 5)
 *
 *  PERFORMANCE GAIN vs Baseline:
 *    - 1 transaction = 5 revocations
 *    - 80% reduction in orderer round-trips
 *
 *  SECURITY GAIN vs Baseline:
 *    - Atomic: either all 5 certs revoked or none are \u2014 prevents
 *      partial-revocation attacks
 *    - BatchID in audit trail = forensic traceability of bulk revocations
 *    - MVCC conflicts eliminated (5x fewer concurrent writes)
 *
 *  MVCC SAFETY:
 *    Targets BCERT_{workerIdx}_{batchIndex}_{1..5} \u2014 same keys as
 *    BatchIssueCertificates (Round 7). Each worker owns its own range.
 *    Idempotent: not-found or already-revoked certs \u2192 counted as success.
 *
 *  Chaincode function: BatchRevokeCertificates(idsJSON string) *BatchResult
 *  contractArguments: [JSON.stringify(["BCERT_...", ...])]
 */
class BatchRevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.batchIndex = 0;
        this.workerIdx  = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.batchIndex = 0;
        this.workerIdx  = workerIndex;
    }

    async submitTransaction() {
        this.batchIndex++;
        const BATCH_SIZE = 5;

        // Revoke the same BCERT IDs that were issued in Round 7 (BatchIssueCertificates)
        // Pattern: BCERT_{workerIdx}_{batchIndex}_{1..5}
        // Each worker owns its own key range \u2014 zero MVCC conflicts
        const ids = [];
        for (let i = 1; i <= BATCH_SIZE; i++) {
            ids.push(`BCERT_${this.workerIdx}_${this.batchIndex}_${i}`);
        }

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'BatchRevokeCertificates',
            contractArguments: [JSON.stringify(ids)],   // single JSON arg = batch of 5 IDs
            readOnly:          false,
            timeout:           240
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new BatchRevokeCertificateWorkload() };
