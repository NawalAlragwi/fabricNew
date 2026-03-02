'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * QueryAllCertificates Workload Module
 * Function: QueryAllCertificates() -> []Certificate (readOnly)
 * RBAC: Public (any org)
 * Guarantee: 0 failures — always returns empty array or full list, never throws
 */
class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async submitTransaction() {
        const request = {
            contractId:        'basic',
            contractFunction:  'QueryAllCertificates',
            contractArguments: [],
            readOnly:          true
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
