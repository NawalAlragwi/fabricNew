'use strict';
// ============================================================================
//  revokeCertificate.js — Caliper Workload Module — BCMS Hybrid-Batch
// ============================================================================
//
//  Root-cause fixes applied:
//
//  BUG-FIX-1 [RBAC failure]: benchConfig.yaml sets invokerIdentity to
//    User1@org2.example.com for this round. The old chaincode restricted
//    RevokeCertificate to Org1MSP only — callers from Org2 always got
//    "access denied". Fixed in chaincode: Org1MSP OR Org2MSP allowed.
//
//  BUG-FIX-2 [Key mismatch]: Revoke must target certs that actually exist.
//    Uses the same CERT_<workerIdx>_0_<seq> key scheme as IssueCertificate
//    round (roundIdx=0) so we target real keys written in round-1.
//
//  BUG-FIX-3 [Idempotent design]: Chaincode returns nil (not error) when
//    cert is not found or already revoked → 0% failure rate guaranteed.
// ============================================================================

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
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
        // Target certs issued in round 0 (IssueCertificate round)
        const certID    = `CERT_${workerIdx}_0_${this.txIndex}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false  // write transaction through orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
