'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * IssueCertificate Workload Module
 * Function: IssueCertificate(id, studentName, degree, issuer, issueDate, certHash)
 * RBAC: Org1MSP only
 * Guarantee: 0 failures — duplicate IDs return nil (idempotent by design)
 */
class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;

        const certID      = `CERT_${this.workerIndex}_${this.txIndex}`;
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = new Date().toISOString().split('T')[0];
        // SHA-256 hash matches what VerifyCertificate expects
        const certHash    = crypto.createHash('sha256').update(certID + studentName).digest('hex');

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',
            // Order must match Go signature: (id, studentName, degree, issuer, issueDate, certHash)
            contractArguments: [certID, studentName, degree, issuer, issueDate, certHash],
            readOnly:          false
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
