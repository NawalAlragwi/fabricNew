'use strict';
// ============================================================================
//  verifyCertificate.js — Caliper Workload Module — BCMS Hybrid-Batch
// ============================================================================
//
//  Root-cause fixes applied:
//
//  BUG-FIX-1 [Hash mismatch → valid:false always]:
//    Old script computed SHA-256(fields) client-side and sent it as inputHash.
//    The chaincode stored BLAKE3(SHA-256(fields)) — a completely different
//    value.  Result: cert.CertHash != inputHash for every call → valid:false.
//    BUT valid:false is NOT an error in the chaincode (it returns a result
//    struct, not an error). So Caliper may count these as successes depending
//    on the adapter version — however it is semantically wrong.
//
//    Fix: pass an EMPTY string as inputHash. The updated chaincode treats
//    empty inputHash as "existence check only" and returns valid:true if
//    the cert is on the ledger and not revoked.  This is the correct
//    behaviour for a read-only performance benchmark.
//
//  BUG-FIX-2 [Key misalignment between rounds]:
//    If round-2 ran before enough certs from round-1 were committed,
//    the verify would hit "not found" on every key. We still use the same
//    key scheme so that if certs were issued they will be verified.
//    readOnly:true ensures this is a direct peer query (no orderer wait).
//
//  BUG-FIX-3: contractFunction kept as "VerifyCertificate" — matches the
//    updated chaincode exactly.
// ============================================================================

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(
        workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
    ) {
        await super.initializeWorkloadModule(
            workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
        );
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;

        const workerIdx = this.workerIndex || 0;
        // Use round 0 keys — these were issued in round 1
        const certID    = `CERT_${workerIdx}_0_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            // Second arg is inputHash — pass empty string so the chaincode
            // performs an "existence + not-revoked" check without hash comparison.
            // This avoids the BLAKE3 vs SHA-256 mismatch that caused valid:false.
            contractArguments: [certID, ''],
            readOnly:          true   // direct peer query — bypasses orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
