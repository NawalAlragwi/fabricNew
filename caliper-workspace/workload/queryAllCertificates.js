'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  QueryAllCertificates Workload Module — BCMS Benchmark (mirage branch)
 * ══════════════════════════════════════════════════════════════════════
 *  Function  : QueryAllCertificates() → []*Certificate
 *  RBAC      : Public read (any org)
 *  Guarantee : 0 failures — returns empty slice on empty ledger (never nil)
 *  Note      : readOnly:true — direct peer query, bypasses orderer
 *  Index     : Uses CouchDB indexCertificates (docType, IssueDate)
 * ══════════════════════════════════════════════════════════════════════
 */
class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'QueryAllCertificates',
            contractArguments: [],      // no args — Go func takes only ctx
            readOnly:          true,     // essential: prevents orderer bottleneck
            timeout:           240
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
