'use strict';
// ============================================================================
//  getCertificatesByStudent.js — Caliper Workload Module — BCMS Hybrid-Batch
// ============================================================================
//
//  Root-cause fix:
//
//  BUG-FIX-1 [Function not found]: The old hybrid chaincode had no
//    GetCertificatesByStudent function → 100% failure for this round.
//    Fixed in chaincode.
//
//  BUG-FIX-2 [Key alignment]: Uses STU_<workerIdx>_0_<seq> to query
//    students that were registered during round-0 (IssueCertificate).
//    readOnly:true → direct peer query.
// ============================================================================

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class GetCertificatesByStudentWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(
        workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
    ) {
        await super.initializeWorkloadModule(
            workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
        );
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;

        const workerIdx = this.workerIndex || 0;
        // Query students whose certs were issued in round-0
        const studentID = `STU_${workerIdx}_0_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'GetCertificatesByStudent',
            contractArguments: [studentID],
            readOnly:          true
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };
