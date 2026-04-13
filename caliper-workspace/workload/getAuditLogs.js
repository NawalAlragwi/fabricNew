'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  GetAuditLogs Workload — BCMS Hybrid-Batch Benchmark (mirage-batch)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature (smartcontract_hybrid.go):
 *    GetAuditLogs() ([]*AuditLog, error)
 *
 *  readOnly:true — CouchDB rich query, no orderer involvement.
 *  Returns empty [] when audit logging is disabled — never returns error.
 *
 *  Note: Audit logging is disabled in benchmarks (see auditLog() in
 *  smartcontract_hybrid.go) to eliminate write amplification that would
 *  create unnecessary MVCC pressure on AUDIT_ keys.
 * ══════════════════════════════════════════════════════════════════════════
 */
class GetAuditLogsWorkload extends WorkloadModuleBase {
    async submitTransaction() {
        return this.sutAdapter.sendRequests({
            contractId:        'basic',
            contractFunction:  'GetAuditLogs',
            contractArguments: [],
            readOnly:          true,
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new GetAuditLogsWorkload() };
