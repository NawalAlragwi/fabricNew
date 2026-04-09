'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  GetAuditLogs Workload Module — BCMS Benchmark (mirage branch)
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : GetAuditLogs() → []*AuditLog
 *  RBAC      : Public read (any org can query audit trail)
 *
 *  Zero-failure guarantee:
 *    - chaincode NEVER returns a Go error — always returns empty slice
 *    - readOnly:true bypasses orderer for maximum throughput
 *    - Uses range scan on AUDIT_ prefix (faster than CouchDB rich query)
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
            readOnly:          true,   // direct peer query — no orderer overhead
            timeout:           240
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetAuditLogsWorkload() };
