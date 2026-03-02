'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * VerifyCertificate Workload Module
 * Function: VerifyCertificate(id, certHash) -> (bool, error)
 * RBAC: Public (any org)
 * Guarantee: 0 failures — returns false (not error) when cert not found
 */
class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;

        const certID      = `CERT_${this.workerIndex}_${this.txIndex}`;
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        // Must match the same hash used during IssueCertificate
        const certHash    = crypto.createHash('sha256').update(certID + studentName).digest('hex');

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
