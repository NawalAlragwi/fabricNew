'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  GetCertificatesByStudent Workload Module — BCMS Benchmark
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : GetCertificatesByStudent(studentId) → []*Certificate
 *  RBAC      : Public read (any org)
 *
 *  Zero-failure guarantee:
 *    - chaincode returns empty slice (never error) when no certs found
 *    - readOnly:true bypasses orderer
 *
 *  StudentID pattern: STU_{workerIndex}_{txIndex}
 *    Matches the studentId stored by IssueCertificate workload in round 1.
 *    CouchDB query field: "studentId" (lowercase 'i') — matches JSON tag.
 * ══════════════════════════════════════════════════════════════════════
 */
class GetCertificatesByStudentWorkload extends WorkloadModuleBase {
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

        // STU_{workerIndex}_{txIndex} — same pattern as IssueCertificate
        // so this query returns actual certificates from the ledger.
        const studentID = `STU_${workerIdx}_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'GetCertificatesByStudent',
            contractArguments: [studentID],
            readOnly:          true   // direct peer query — no orderer overhead
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };