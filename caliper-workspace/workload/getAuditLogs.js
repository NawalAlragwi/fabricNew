'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  GetAuditLogs Workload — BCMS Benchmark (all scenarios)
 *  v2.0 — FIX-CONTRACTID: reads contractId from roundArguments
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature:
 *    GetAuditLogs() ([]*AuditLog, error)
 *
 *  FIX-CONTRACTID (v2.0):
 *  Previous version hardcoded contractId: 'basic' — would always call the
 *  wrong chaincode regardless of which scenario is running.
 *  Fixed: reads contractId from roundArguments (set in benchConfig YAML).
 *
 *  readOnly: true — CouchDB rich query, no orderer involvement.
 *  Returns empty [] when no audit logs exist — never returns error.
 *
 *  Note: With v12.0 chaincode (FIX-AUDIT), writeAudit is now active for
 *  both IssueCertificate and RevokeCertificate, so audit logs will exist
 *  after the issue rounds complete.
 * ══════════════════════════════════════════════════════════════════════════
 */
class GetAuditLogsWorkload extends WorkloadModuleBase {
    async submitTransaction() {
        return this.sutAdapter.sendRequests({
            contractId: this.roundArguments.contractId || 'bcms-sha256',
            contractFunction: 'GetAuditLogs',
            contractArguments: [],
            readOnly: true,
        });
    }

    async cleanupWorkloadModule() { }
}

module.exports = { createWorkloadModule: () => new GetAuditLogsWorkload() };