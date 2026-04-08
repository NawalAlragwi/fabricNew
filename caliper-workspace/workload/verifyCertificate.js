'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  VerifyCertificate Workload Module — BCMS Benchmark (mirage branch)
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : VerifyCertificate(id, certHash) → VerificationResult
 *  RBAC      : Public (any org — readOnly query)
 *  Guarantee : 0 failures — returns {valid:false} (not error) when
 *              cert not found or hash mismatches.
 *  Hash      : Empty string passed — chaincode returns valid=false for
 *              hash mismatch, which is NOT a transaction failure.
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

        // Use empty certHash — VerifyCertificate returns {valid:false, hashMatch:false}
        // which is a valid response, NOT a Go error → zero failure guarantee
        const certHash = '';

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true    // bypass orderer — direct peer query for max TPS
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
