'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════════
 *  RevokeCertificate Workload Module — BCMS BLAKE3 Benchmark
 *  Branch: fabric-blake3-new
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  Function  : RevokeCertificate(id) → error
 *  RBAC      : Org2MSP authorized (policy: OR('Org1MSP.peer','Org2MSP.peer'))
 *  Guarantee : 0 failures — idempotent (nil when cert not found or revoked)
 *  Invoker   : User1@org2.example.com
 *
 *  ID Pattern: CERT_B3_{workerIndex}_{txIndex} — must match IssueCertificate
 * ══════════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

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

        // ── ID Pattern: CERT_B3_{workerIndex}_{txIndex} ───────────────────────
        // Revoke certificates issued in Round 1 (IssueCertificate)
        const certID = `CERT_B3_${workerIdx}_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false    // write transaction — goes through orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed — idempotent design handles duplicates
    }
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
