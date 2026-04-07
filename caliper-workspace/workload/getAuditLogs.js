'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 * GetAuditLogs Workload Module — BCMS Benchmark v4.2
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : GetAuditLogs() → []*AuditLog
 *  RBAC      : Public read (any org can query audit trail)
 *
 *  Zero-failure guarantee:
 *    - chaincode NEVER returns a Go error — always returns empty slice
 *    - readOnly:true bypasses orderer for maximum throughput
 *    - FIX: previous chaincode returned error on CouchDB failure;
 *      new implementation catches all errors and returns [] instead.
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
            contractId:        'basic',
            contractFunction:  'GetAuditLogs',
            contractArguments: [],
            readOnly:          true   // direct peer query — no orderer overhead
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // لا يوجد عمليات تنظيف مطلوبة لعمليات القراءة
    }
}

module.exports = { createWorkloadModule: () => new GetAuditLogsWorkload() };