'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════════
 *  QueryAllCertificates Workload Module — BCMS BLAKE3 Benchmark
 *  Branch: fabric-blake3-new
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  Function  : QueryAllCertificates() → []*Certificate
 *  RBAC      : Public read (any org)
 *  Guarantee : 0 failures — returns empty slice on empty ledger (never nil)
 *  Note      : readOnly:true — direct peer query, bypasses orderer
 *
 *  Returns certificates with HashAlgorithm="BLAKE3" after BLAKE3 rounds.
 * ══════════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        const request = {
            contractId:        'basic',
            contractFunction:  'QueryAllCertificates',
            contractArguments: [],      // no args — Go func takes only ctx
            readOnly:          true     // essential: prevents orderer bottleneck
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed
    }
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
