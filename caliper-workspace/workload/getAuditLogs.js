'use strict';
// ============================================================================
//  getAuditLogs.js — Caliper Workload Module — BCMS Hybrid-Batch
//  Chaincode function: GetAuditLogs() → []*AuditLog
// ============================================================================
//
//  No-argument call — chaincode performs a range scan on the "AUDIT_" key
//  prefix and returns all AuditLog entries written by IssueCertificate and
//  RevokeCertificate.
//
//  readOnly:true — direct peer query.
//  Zero-failure: returns empty slice when no audit entries exist yet.
//
//  No functional changes needed — file kept for completeness and alignment
//  with the updated key-range scan in the chaincode (AUDIT_ … AUDIT_~).
// ============================================================================

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class GetAuditLogsWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(
        workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
    ) {
        await super.initializeWorkloadModule(
            workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
        );
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
