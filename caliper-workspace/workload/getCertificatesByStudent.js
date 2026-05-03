'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  GetCertificatesByStudent Workload — BCMS Benchmark (all scenarios)
 *  v2.0 — FIX-CONTRACTID: reads contractId from roundArguments
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature:
 *    GetCertificatesByStudent(studentID string) ([]*Certificate, error)
 *
 *  FIX-CONTRACTID (v2.0):
 *  Previous version hardcoded contractId: 'basic' — would always call the
 *  wrong chaincode regardless of which scenario is running.
 *  Fixed: reads contractId from roundArguments (set in benchConfig YAML).
 *
 *  studentID pattern: STU_{workerIndex}_{txIndex}
 *  Matches the IssueCertificate workload key scheme so queries find real
 *  certificates issued in the preceding round.
 *
 *  readOnly: true — CouchDB rich query with compound index.
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
        const w = this.workerIndex || 0;
        const studentID = `STU_${w}_${this.txIndex}`;

        return this.sutAdapter.sendRequests({
            contractId: this.roundArguments.contractId || 'bcms-sha256',
            contractFunction: 'GetCertificatesByStudent',
            contractArguments: [studentID],
            readOnly: true,
        });
    }

    async cleanupWorkloadModule() { }
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };