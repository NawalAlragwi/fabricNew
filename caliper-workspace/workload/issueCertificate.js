'use strict';
// ============================================================================
//  issueCertificate.js — Caliper Workload Module — BCMS Hybrid-Batch
// ============================================================================
//
//  Root-cause fixes applied:
//
//  BUG-FIX-1: Old script sent individual fields (id, studentID, …) as separate
//    contractArguments strings, BUT the new hybrid chaincode's IssueCertificate
//    expects ONE JSON string (array or object of Certificate structs).
//    Result before fix: "incorrect number of arguments" → 100% failure.
//
//  BUG-FIX-2: Caliper benchConfig round-1 calls contractFunction "IssueCertificate"
//    (NOT "IssueCertificateBatch").  Kept consistent.
//
//  BUG-FIX-3: MVCC fix — each worker now uses a globally unique key scheme:
//    CERT_<workerIndex>_<roundIndex>_<seq>
//    Two workers will never share the same cert ID in the same block,
//    eliminating all MVCC_READ_CONFLICT phantom collisions.
//
//  BUG-FIX-4: Hash is intentionally NOT computed here. The chaincode
//    recomputes ComputeHybridHash(SHA-256 ∘ BLAKE3) internally, so the
//    stored CertHash is always authoritative. Sending a SHA-256 client-side
//    hash was the old mismatch bug; now CertHash field is left blank and the
//    chaincode fills it.
//
//  Batch strategy: batchSize certs are packed into one JSON array and sent
//  as a single Fabric transaction → high TPS with low per-cert overhead.
// ============================================================================

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.batchSize = 10; // certificates per Fabric transaction
    }

    async initializeWorkloadModule(
        workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
    ) {
        await super.initializeWorkloadModule(
            workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext
        );
        this.txIndex    = 0;
        this.batchSize  = (roundArguments && roundArguments.batchSize) || 10;
    }

    async submitTransaction() {
        const batch     = [];
        const workerIdx = this.workerIndex || 0;
        const roundIdx  = this.roundIndex  || 0;
        const today     = new Date().toISOString().split('T')[0];

        for (let i = 0; i < this.batchSize; i++) {
            this.txIndex++;

            // ── Globally unique key: no two workers can ever produce the same ID ──
            const certID      = `CERT_${workerIdx}_${roundIdx}_${this.txIndex}`;
            const studentID   = `STU_${workerIdx}_${roundIdx}_${this.txIndex}`;
            const studentName = `Student_${workerIdx}_${this.txIndex}`;

            // CertHash intentionally left empty — chaincode computes
            // BLAKE3(SHA-256(fields)) and stores the authoritative digest.
            batch.push({
                ID:          certID,
                StudentID:   studentID,
                StudentName: studentName,
                Degree:      'Bachelor of Computer Science',
                Issuer:      'Digital University',
                IssueDate:   today,
                CertHash:    '',   // chaincode fills this
                Signature:   `SIG_${certID}`
            });
        }

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',   // single entry point (batch-aware)
            contractArguments: [JSON.stringify(batch)], // one JSON-array argument
            readOnly:          false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
