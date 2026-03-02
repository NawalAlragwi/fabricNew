/*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    /**
    * Initialize the workload module with the given parameters.
    * @param {number} workerIndex The 0-based index of the worker bound to this workload module.
    * @param {number} totalWorkers The total number of workers.
    * @param {number} roundIndex The 0-based index of the currently executed round.
    * @param {Object} roundArguments The user-provided arguments for the round from the benchmark configuration file.
    * @param {BlockchainInterface} sutAdapter The adapter of the underlying SUT.
    * @param {Object} sutContext The custom context for the SUT adapter.
    * @async
    */
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    /**
    * Assemble and submit a Hyperledger Fabric transaction.
    * @async
    */
    async submitTransaction() {
        const queryArgs = {
            contractId: 'certificate', // تأكد أن هذا الاسم يطابق اسم العقد (chaincode name) في شبكتك
            contractFunction: 'QueryAllCertificates',
            contractArguments: [],
            readOnly: true
        };

        try {
            // استخدام evaluateTransaction يضمن تسجيل النتيجة كنجاح (Succ) في التقرير
            // ويمنع احتسابها كفشل في حال تأخر الـ Orderer لأن الاستعلام لا يحتاجه
            await this.sutAdapter.evaluateTransaction(queryArgs.contractId, queryArgs.contractFunction, queryArgs.contractArguments);
        } catch (error) {
            // تسجيل الخطأ في حال وجود مشكلة حقيقية في الاتصال
            console.error(`Worker ${this.workerIndex}: Error during QueryAllCertificates: ${error.message}`);
        }
    }

    /**
    * Clean up the workload module at the end of the round.
    * @async
    */
    async cleanupWorkloadModule() {
        // لا يوجد متطلبات تنظيف خاصة هنا
    }
}

function createWorkloadModule() {
    return new QueryAllCertificatesWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
