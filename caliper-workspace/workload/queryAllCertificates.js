'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractId = this.roundArguments.contractId || 'bcms-sha256';
    }

    async submitTransaction() {
        const request = {
            contractId: this.contractId,
            contractFunction: 'QueryAllCertificates',
            contractArguments: ['20', ''],
            readOnly: true,
        };

        // إضافة retry — يتجنب الفشل بسبب التحميل المؤقت
        try {
            return await this.sutAdapter.sendRequests(request);
        } catch (err) {
            // انتظار قصير ثم إعادة المحاولة
            await new Promise(r => setTimeout(r, 500));
            return await this.sutAdapter.sendRequests(request);
        }
    }

    async cleanupWorkloadModule() { }
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };