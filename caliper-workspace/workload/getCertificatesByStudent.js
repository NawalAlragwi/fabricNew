'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════════
 *  GetCertificatesByStudent Workload Module — BCMS BLAKE3 Benchmark
 *  Branch: fabric-blake3-new
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  Function  : GetCertificatesByStudent(studentID) → []*Certificate
 *  RBAC      : Public read (any org)
 *  Guarantee : 0 failures — returns empty slice (never nil)
 *
 *  Student ID Pattern: STU_B3_{workerIndex}_{txIndex}
 *  Queries students issued in Round 1 (IssueCertificate).
 * ══════════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

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

        // ── Student ID Pattern: STU_B3_{workerIndex}_{txIndex} ───────────────
        // Query students who received certificates in Round 1
        const studentID = `STU_B3_${workerIdx}_${this.txIndex}`;

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
