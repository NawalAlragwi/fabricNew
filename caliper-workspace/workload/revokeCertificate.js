'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  RevokeCertificate Workload Module — BCMS Benchmark (mirage-new)
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : RevokeCertificate(id) → error
 *  RBAC      : Org1MSP or Org2MSP authorized
 *  Invoker   : User1@org2.example.com
 *
 *  MVCC-Safe Design (One-to-One Mapping):
 *    - Each worker revokes ONLY the certificates it issued in Round 1
 *    - Pattern: CERT_{workerIndex}_{txIndex}
 *    - Worker 0 revokes CERT_0_1, CERT_0_2, CERT_0_3, ...
 *    - Worker 1 revokes CERT_1_1, CERT_1_2, CERT_1_3, ...
 *    - Worker 2 revokes CERT_2_1, CERT_2_2, CERT_2_3, ...
 *    - ZERO key collision between concurrent transactions
 *
 *  Zero-failure guarantee:
 *    - chaincode is idempotent: cert-not-found → nil (not error)
 *    - cert already revoked    → nil (not error)
 *    - MVCC conflicts eliminated by worker-specific key partitioning
 * ══════════════════════════════════════════════════════════════════════
 */
class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        // Reset txIndex to 0 at the start of each round
        // This ensures we revoke the same certificates we issued in Round 1
        this.txIndex = 0;
        
        // Store worker index to ensure consistent ID generation
        this.workerIdx = workerIndex;
    }

    async submitTransaction() {
        this.txIndex++;
        
        // CRITICAL: Use consistent worker index to avoid MVCC conflicts
        // Each worker revokes ONLY its own certificates from Round 1
        // Pattern: CERT_{workerIndex}_{txIndex}
        const certID = `CERT_${this.workerIdx}_${this.txIndex}`;

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false,   // write transaction — goes through orderer
            // invokerIdentity is set via txOptions in benchConfig.yaml
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed for revocation workload
    }
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
