'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async submitTransaction() {
        return this.sutAdapter.sendRequests({
            contractId:        'basic',           // ✅ العودة إلى basic للسيناريو 2
            contractFunction:  'QueryAllCertificates',
            contractArguments: ['20', ''],        // ✅ pageSize + bookmark مطلوبان
            readOnly:          true,
        });
    }
    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
