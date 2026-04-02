'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ══════════════════════════════════════════════════════════════════════════════
//  GetCertificatesByStudent Workload — BCMS BLAKE3 Benchmark
//  Branch: fabric-blake3
//
//  No hashing required — CouchDB rich query by student ID.
//  Student ID pattern: STU_{workerIndex}_{txIndex}
//    Matches IssueCertificate workload — queries students from Round 1.
//
//  readOnly: true — CouchDB rich query with composite index.
//  Returns empty slice [] when student has no certs — never returns error.
//
//  Function signature (smartcontract_blake3.go):
//    GetCertificatesByStudent(studentId) ([]*Certificate, error)
// ══════════════════════════════════════════════════════════════════════════════

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
        const w = this.workerIndex || 0;
        // Query students from Round 1 BLAKE3 issue batch — same ID pattern
        const studentID = `STU_${w}_${this.txIndex}`;

        return this.sutAdapter.sendRequests({
            contractId:        'basic',
            contractFunction:  'GetCertificatesByStudent',
            contractArguments: [studentID],
            readOnly:          true,
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };
