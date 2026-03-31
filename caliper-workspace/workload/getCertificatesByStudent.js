'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  GetCertificatesByStudent Workload — BCMS Hybrid-Batch (mirage-batch)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature (smartcontract_hybrid.go):
 *    GetCertificatesByStudent(studentId) ([]*Certificate, error)
 *
 *  IMPORTANT: The hybrid chaincode uses lowercase JSON field names.
 *  studentId (camelCase) matches the CouchDB selector field "studentId"
 *  which is the Go struct tag: json:"studentId"
 *
 *  readOnly:true — CouchDB rich query with composite index.
 *  Returns empty slice [] when student has no certs — never returns error.
 * ══════════════════════════════════════════════════════════════════════════
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
        const w         = this.workerIndex || 0;
        // Query students from Round 1 issue batch — same ID pattern
        const studentID = `STU_${w}_${this.txIndex}`;

        return this.sutAdapter.sendRequests({
            contractId:        'bcms-hybrid',
            contractFunction:  'GetCertificatesByStudent',
            contractArguments: [studentID],
            readOnly:          true,
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };
