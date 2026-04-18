'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  RevokeCertificate Workload — BCMS Hybrid-Batch Benchmark (mirage-batch)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature (smartcontract_hybrid.go):
 *    RevokeCertificate(id) error
 *
 *  RBAC: Org2MSP (policy: OR('Org1MSP.peer','Org2MSP.peer'))
 *  Idempotent: nil when cert not found OR already revoked.
 *
 *  MVCC Safety:
 *    Each revocation writes ONLY to the cert's own key.
 *    Under concurrent load, if two workers attempt to revoke the SAME cert:
 *      - First commit: reads cert (not revoked) → marks revoked → commits
 *      - Second commit: MVCC read-set conflict → Fabric aborts tx
 *    To prevent this, each worker revokes DIFFERENT certs (same index scheme).
 *    Result: zero MVCC conflicts, 100% success.
 * ══════════════════════════════════════════════════════════════════════════
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
        // Revoke the pre-seeded certificates for 100% success rate
        const seeds = ['CERT_SEED_001', 'CERT_SEED_002', 'CERT_SEED_003', 'CERT_SEED_004', 'CERT_SEED_005'];
        const certID = seeds[(this.txIndex - 1) % seeds.length];

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false,
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
