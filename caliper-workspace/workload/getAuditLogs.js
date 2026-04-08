'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 * GetAuditLogs Workload Module — BCMS Benchmark v4.2
 * ══════════════════════════════════════════════════════════════════════
 * Function  : GetAuditLogs() → []*AuditLog
 * Purpose   : Performance testing of immutable audit trail retrieval.
 * Guarantee : Optimized for 0% failure rate.
 * ══════════════════════════════════════════════════════════════════════
 */
class GetAuditLogsWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'GetAuditLogs',
            contractArguments: [],
            // 'readOnly: true' أساسي لضمان سرعة الاستجابة وعدم استهلاك موارد الـ Orderer
            readOnly:          true 
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // لا يوجد عمليات تنظيف مطلوبة لعمليات القراءة
    }
}

module.exports = { createWorkloadModule: () => new GetAuditLogsWorkload() };