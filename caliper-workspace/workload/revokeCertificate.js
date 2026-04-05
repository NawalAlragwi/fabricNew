'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ══════════════════════════════════════════════════════════════════════════════
//  RevokeCertificate Workload — BCMS BLAKE3 Benchmark
//  Branch: fabric-blake3
//
//  No hashing required for revocation — only certificate ID is needed.
//  ID pattern: CERT_B3_{workerIndex}_{txIndex}
//    Matches IssueCertificate workload — revokes certs issued in Round 1.
//
//  RBAC: Org2MSP (policy: OR('Org1MSP.peer','Org2MSP.peer'))
//  Idempotent: nil when cert not found OR already revoked.
//
//  MVCC Safety:
//    Each worker revokes ONLY its own certs (same index scheme).
//    No cross-worker MVCC conflicts — 100% success rate.
//
//  Audit logging: DISABLED in chaincode (benchmark optimization).
//
//  Function signature (smartcontract_blake3.go):
//    RevokeCertificate(id) error
// ══════════════════════════════════════════════════════════════════════════════

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
        const w = this.workerIndex || 0;
        // CERT_B3_ prefix: matches BLAKE3 IssueCertificate workload exactly
        // Each worker revokes ONLY its own certs → zero cross-worker MVCC conflict
        const certID = `CERT_B3_${w}_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false, // write transaction — goes through orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
