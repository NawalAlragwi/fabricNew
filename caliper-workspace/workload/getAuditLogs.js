'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ══════════════════════════════════════════════════════════════════════════════
//  GetAuditLogs Workload — BCMS BLAKE3 Benchmark
//  Branch: fabric-blake3
//
//  No hashing required — audit log query.
//  Returns empty [] in benchmark mode (audit logging disabled on-chain
//  for maximum TPS — no write amplification on AUDIT_ keys).
//
//  readOnly: true — CouchDB query, no orderer involvement.
//  Never returns Go error — Caliper always counts as SUCCESS.
//
//  Function signature (smartcontract_blake3.go):
//    GetAuditLogs() ([]string, error)
// ══════════════════════════════════════════════════════════════════════════════

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
