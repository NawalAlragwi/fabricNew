'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  GetCertificatesByStudent Workload — BCMS BLAKE3 (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: chaincode-bcms/blake3 (deployed as bcms-blake3)
 *
 *  Function signature (smartcontract_blake3.go):
 *    GetCertificatesByStudent(studentID) ([]*Certificate, error)
 *
 *  readOnly:true — CouchDB rich query with composite index.
 *  Returns empty slice [] when student has no certs — never returns error.
 *
 *  CouchDB Index Alignment:
 *    The chaincode selector uses:
 *      {"docType": "certificate", "StudentID": "<studentID>"}
 *    This matches the index on ["docType", "StudentID", "Issuer"].
 *    CouchDB resolves with the index — no full-table scan.
 *    StudentID is the Go struct JSON tag; workload sends matching value.
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
        // StudentID must match what IssueCertificate wrote with the same pattern.
        // Chaincode CouchDB selector: {"docType":"certificate","StudentID":"<studentID>"}
        // → hits the index (docType + StudentID are first two index fields).
        const studentID = `STU_${w}_${this.txIndex}`;

        return this.sutAdapter.sendRequests({
            contractId:        'bcms-blake3',
            contractFunction:  'GetCertificatesByStudent',
            contractArguments: [studentID],
            readOnly:          true,
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };
