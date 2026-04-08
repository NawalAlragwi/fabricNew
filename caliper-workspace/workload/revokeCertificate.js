'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
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
        
        // يجب أن يتطابق هذا النمط مع ما تم استخدامه في جولة IssueCertificate
        // إذا لم تستخدمي التاريخ هناك، احذفي الجزء الأخير هنا
        const certID = `CERT_${workerIdx}_${this.txIndex}`; 

        const request = {
            contractId:         'bcms-hybrid',
            contractFunction:   'RevokeCertificate',
            contractArguments:  [certID],
            readOnly:           false // هذه معاملة كتابة (Write) تمر عبر الـ Orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // تصميم Idempotent لا يحتاج تنظيف
    }
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };