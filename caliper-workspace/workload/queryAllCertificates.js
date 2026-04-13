'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  QueryAllCertificates Workload — BCMS Hybrid-Batch Benchmark (mirage-batch)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature (smartcontract_hybrid.go):
 *    QueryAllCertificates() ([]*Certificate, error)
 *
 *  readOnly:true — CouchDB rich query direct to peer, no orderer.
 *  Returns empty slice [] on empty ledger — NEVER returns Go error.
 *  Caliper counts SUCCESS for any non-error response (including empty []).
 * ══════════════════════════════════════════════════════════════════════════
 */
class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async submitTransaction() {
        return this.sutAdapter.sendRequests({
            contractId:        'basic',
            contractFunction:  'QueryAllCertificates',
            contractArguments: [], // Go func takes only ctx — no args
            readOnly:          true,
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
