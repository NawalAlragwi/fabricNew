'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ══════════════════════════════════════════════════════════════════════════════
//  QueryAllCertificates Workload — BCMS BLAKE3 Benchmark
//  Branch: fabric-blake3
//
//  No hashing required — pure CouchDB rich query.
//  Returns all certificates with HashAlgorithm: "BLAKE3" in BLAKE3 mode.
//
//  readOnly: true — direct peer query, bypasses orderer for max TPS.
//  Returns empty slice [] on empty ledger — NEVER returns Go error.
//  Caliper counts SUCCESS for any non-error response (including empty []).
//
//  Function signature (smartcontract_blake3.go):
//    QueryAllCertificates() ([]*Certificate, error)
// ══════════════════════════════════════════════════════════════════════════════

class QueryAllCertificatesWorkload extends WorkloadModuleBase {

    async submitTransaction() {
        return this.sutAdapter.sendRequests({
            contractId:        'basic',
            contractFunction:  'QueryAllCertificates',
            contractArguments: [], // Go func takes only ctx — no args
            readOnly:          true, // essential: prevents orderer bottleneck
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
