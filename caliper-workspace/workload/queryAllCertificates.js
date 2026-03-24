'use strict';
// ============================================================================
//  queryAllCertificates.js — Caliper Workload Module — BCMS Hybrid-Batch
// ============================================================================
//
//  Root-cause fix:
//
//  BUG-FIX-1 [Function not found]: The old hybrid chaincode had no
//    QueryAllCertificates function → 100% failure for this round.
//    Fixed in chaincode. Workload is otherwise correct (readOnly:true,
//    no args, contractFunction name matches chaincode exactly).
//
//  Design: QueryAllCertificates uses GetStateByRange("","") which is
//    safe on both CouchDB and LevelDB. It returns [] on empty ledger.
//    readOnly:true → direct peer query, no orderer bottleneck.
// ============================================================================

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
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
            contractFunction:  'QueryAllCertificates',
            contractArguments: [],   // no arguments — chaincode takes only ctx
            readOnly:          true  // direct peer query, bypasses orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };
