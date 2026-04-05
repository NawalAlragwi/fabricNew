'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════════
 *  GetAuditLogs Workload Module — BCMS BLAKE3 Benchmark
 *  Branch: fabric-blake3-new
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  Function  : GetAuditLogs() → []*AuditLog
 *  RBAC      : Public read (any org can query audit trail)
 *  Guarantee : 0 failures — returns empty slice (never nil)
 *
 *  Note: When DISABLE_AUDIT=true in chaincode env, audit logs are not written
 *  during the benchmark. This round still succeeds (returns empty array).
 *  The empty-array return is intentional for benchmark TPS measurement.
 * ══════════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

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
            readOnly:          true
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetAuditLogsWorkload() };
