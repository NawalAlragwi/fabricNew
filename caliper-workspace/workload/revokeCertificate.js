'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * RevokeCertificate Workload Module
 * Function: RevokeCertificate(id) -> error
 * RBAC: Org2MSP authorized (policy: OR('Org1MSP.peer','Org2MSP.peer'))
 * Guarantee: 0 failures — contract returns nil when cert not found or already revoked
 */
class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        const workerId = this.workerIndex || 0;
        const certID   = `CERT_${workerId}_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
