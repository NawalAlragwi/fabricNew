'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }
    async submitTransaction() {
        // contractId يُقرأ من YAML arguments → S1 يستخدم bcms-sha256، S2 يستخدم bcms-blake3
        return this.sutAdapter.sendRequests({
            contractId:        this.roundArguments.contractId || 'bcms-sha256',
            contractFunction:  'QueryAllCertificates',
            contractArguments: ['20', ''],
            readOnly:          true,
        });
    }
    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
