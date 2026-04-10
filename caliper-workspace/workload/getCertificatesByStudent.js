'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  GetCertificatesByStudent Workload Module — BCMS Benchmark (mirage)
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : GetCertificatesByStudent(studentID) → []*Certificate
 *  RBAC      : Public read (any org)
 *  Index     : Uses CouchDB indexStudentId (docType, StudentID, IssueDate)
 *
 *  Zero-failure guarantee:
 *    - chaincode returns empty slice (never error) when no certs found
 *    - readOnly:true bypasses orderer
 *
 *  StudentID pattern: STU_{workerIndex}_{txIndex}
 *    Matches the StudentID stored by IssueCertificate workload in round 1.
 *    CouchDB query field: "StudentID" (uppercase) — matches JSON tag.
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

        // BCERT_{workerIndex}_{batchIndex}_{i} — same pattern as BatchIssueCertificate
        // so this query returns actual certificates from the ledger.
        const studentID = `BSTU_${workerIdx}_${this.txIndex}_1`;

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'GetCertificatesByStudent',
            contractArguments: [studentID],
            readOnly:          true,   // direct peer query — no orderer overhead
            timeout:           240
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };
