'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  RevokeCertificate Workload Module — BCMS Benchmark
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : RevokeCertificate(id) → error
 *  RBAC      : Org1MSP or Org2MSP authorized
 *  Invoker   : User1@org2.example.com
 *
 *  Zero-failure guarantee:
 *    - chaincode is idempotent: cert-not-found → nil (not error)
 *    - cert already revoked    → nil (not error)
 *    - RevokeCertificate runs AFTER IssueCertificate round so certs exist
 *
 *  ID pattern: CERT_{workerIndex}_{txIndex}
 *    Must match IssueCertificate workload exactly so that certs issued
 *    in round 1 are revocable in round 4.
 * ══════════════════════════════════════════════════════════════════════
 */
class RevokeCertificateWorkload extends WorkloadModuleBase {
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
        const workerIdx = this.workerIndex || 0;

        // CERT_{workerIndex}_{txIndex} — same pattern as IssueCertificate
        // ensures we are revoking certs that were actually issued in round 1.
        const certID = `CERT_${workerIdx}_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false   // write transaction — goes through orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };