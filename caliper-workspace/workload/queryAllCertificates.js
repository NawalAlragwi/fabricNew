'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        // بناء الطلب بالتنسيق الذي يفهمه محول Caliper (SUT Adapter)
        const request = {
            contractId: 'certificate', 
            contractFunction: 'QueryAllCertificates',
            contractArguments: [],
            readOnly: true // ضروري جداً لضمان عدم الذهاب للـ Orderer وتسريع الاختبار
        };

        try {
            // التعديل الجوهري: استخدام sendRequests هو الذي يضمن ظهور عدد المعاملات 
            // الناجحة في التقرير (Success Count > 0)
            await this.sutAdapter.sendRequests(request);
        } catch (error) {
            console.error(`Worker ${this.workerIndex}: Error during QueryAllCertificates: ${error.message}`);
        }
    }

    async cleanupWorkloadModule() {
        // لا حاجة لعمليات تنظيف
    }
}

function createWorkloadModule() {
    return new QueryAllCertificatesWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
