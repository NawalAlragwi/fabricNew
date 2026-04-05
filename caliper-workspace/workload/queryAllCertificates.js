'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  QueryAllCertificates Workload — BCMS BLAKE3 Benchmark (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: chaincode-bcms/blake3 (deployed as basic)
 *
 *  Function signature (smartcontract_blake3.go):
 *    QueryAllCertificates() ([]*Certificate, error)
 *
 *  readOnly:true — CouchDB rich query direct to peer, no orderer.
 *  Returns empty slice [] on empty ledger — NEVER returns Go error.
 *  Caliper counts SUCCESS for any non-error response (including empty []).
 *
 *  CouchDB Index Alignment:
 *    The chaincode QueryAllCertificates selector uses:
 *      {"docType": "certificate", "StudentID": {"$gt": ""}, "Issuer": {"$gt": ""}}
 *    This exactly matches the index defined in:
 *      META-INF/statedb/couchdb/indexes/indexCertificates.json
 *    fields: ["docType", "StudentID", "Issuer"]
 *    CouchDB selects the index automatically — no full-table scan.
 * ══════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

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
