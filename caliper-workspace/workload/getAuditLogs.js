'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  GetAuditLogs Workload — BCMS BLAKE3 Benchmark (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: chaincode-bcms/blake3 (deployed as basic)
 *
 *  Function signature (smartcontract_blake3.go):
 *    GetAuditLogs() ([]*AuditLog, error)
 *
 *  readOnly:true — GetStateByRange("AUDIT_", "AUDIT_~") range scan,
 *  bypasses orderer for maximum TPS.
 *  Returns empty [] when no audit records exist — never returns error.
 *
 *  Note: The blake3 chaincode uses key-range scan for audit logs
 *  (GetStateByRange) rather than CouchDB rich query, which is faster
 *  for sequential key access patterns and doesn't require an index.
 * ══════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

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
