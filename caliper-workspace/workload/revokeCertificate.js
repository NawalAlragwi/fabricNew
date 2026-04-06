'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  RevokeCertificate Workload — BCMS BLAKE3 Benchmark (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: chaincode-bcms/blake3 (deployed as basic)
 *
 *  Function signature (smartcontract_blake3.go):
 *    RevokeCertificate(id) error
 *
 *  RBAC: Any MSP (Org1 or Org2) may revoke per chaincode policy.
 *  Idempotent: nil when cert not found OR already revoked.
 *
 *  MVCC Safety:
 *    Each worker revokes ONLY its own CERT_{worker}_{index} keys.
 *    No cross-worker key collision → zero MVCC_READ_CONFLICT.
 *
 *  CouchDB Index: RevokeCertificate uses GetState (key lookup) then
 *  PutState — no rich query. Index is not used here but the updated
 *  document still carries docType/StudentID/Issuer for future queries.
 * ══════════════════════════════════════════════════════════════════════════
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
        const w = this.workerIndex || 0;
        // Revoke certs issued in Round 1 — same ID pattern: CERT_{worker}_{index}
        // Each worker revokes ONLY its own certs → no cross-worker MVCC conflict
        const certID = `CERT_${w}_${this.txIndex}`;

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
