'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

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
        const workerIdx = this.workerIndex || 0;
        
        // يجب أن نضمن أننا نبحث عن طالب تم إصداره فعلياً في الجولة الأولى
        // النمط STU_0_1, STU_0_2 ... إلخ
        const studentID = `STU_${workerIdx}_${this.txIndex}`;

        const request = {
            contractId:         'basic',
            contractFunction:   'GetCertificatesByStudent',
            contractArguments:  [studentID],
            readOnly:           true // مهم جداً: الاستعلام لا يحتاج موافقة Orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetCertificatesByStudentWorkload() };