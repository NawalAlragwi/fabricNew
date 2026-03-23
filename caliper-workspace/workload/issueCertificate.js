'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════════
 *  issueCertificate.js  —  BCMS Caliper Workload Module
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  Targets : IssueCertificateBatch(certsJSON string) → BatchResult
 *  Contract: basic  (chaincode-bcms/hybrid-batch/smartcontract_hybrid.go)
 *  Access  : Org1MSP (User1@org1.example.com)
 *
 *  BATCHING DESIGN
 *  ───────────────
 *  Standard model:   N certs  =  N blockchain transactions  =  N ordering cycles
 *  Hybrid-Batch:     N certs  =  1 blockchain transaction   =  1 ordering cycle
 *
 *  With batchSize = 5 (default):
 *    - Each Caliper "send" wraps 5 certificates into ONE Fabric Tx
 *    - Orderer overhead reduced by 5×
 *    - Effective certificate throughput ≈ TPS × batchSize
 *    - World State PutState ops: still N (one per cert) — integrity unchanged
 *
 *  Parameter synchronisation with smartcontract_hybrid.go:
 *    • contractFunction : 'IssueCertificateBatch'          ✓ matches Go func name
 *    • contractArguments: [JSON.stringify(batch)]           ✓ matches (certsJSON string)
 *    • readOnly         : false                             ✓ write operation
 *    • JSON fields      : id, student_id, student_name,
 *                         degree, issuer, issue_date        ✓ match Certificate struct tags
 * ══════════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class IssueCertificateBatchWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex  = 0;
        /**
         * batchSize controls how many Certificate objects are included in
         * each single Fabric transaction.  This is the core batching knob.
         *
         * Dissertation note:
         *   batchSize = 1  →  baseline (equivalent to individual IssueCertificate)
         *   batchSize = 5  →  5× reduction in consensus round-trips
         *   batchSize = 10 →  10× reduction (but larger MVCC read-set per Tx)
         */
        this.batchSize = 5;
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
        const workerIdx = this.workerIndex || 0;
        const batch     = [];

        // ── Build the certificate batch ────────────────────────────────────────
        for (let i = 0; i < this.batchSize; i++) {
            this.txIndex++;

            // Unique IDs prevent duplicate-key errors on the ledger
            const certID      = `CERT_W${workerIdx}_T${this.txIndex}_B${i}_${Date.now()}`;
            const studentID   = `STU_W${workerIdx}_T${this.txIndex}_B${i}`;
            const studentName = `Student_${workerIdx}_${this.txIndex}`;

            // Fields MUST match Certificate struct JSON tags in smartcontract_hybrid.go:
            //   id          → cert.ID
            //   student_id  → cert.StudentID
            //   student_name→ cert.StudentName
            //   degree      → cert.Degree
            //   issuer      → cert.Issuer
            //   issue_date  → cert.IssueDate
            batch.push({
                id:           certID,
                student_id:   studentID,
                student_name: studentName,
                degree:       'PhD in Computer Science',
                issuer:       'Sana University',
                issue_date:   new Date().toISOString().split('T')[0]
                // NOTE: cert_hash, hash_algo, is_revoked, doc_type,
                //       created_at, updated_at, tx_id are computed by chaincode
            });
        }

        // ── Caliper request — aligned with IssueCertificateBatch signature ─────
        // func (s *SmartContract) IssueCertificateBatch(
        //     ctx contractapi.TransactionContextInterface,
        //     certsJSON string,              ← contractArguments[0]
        // ) (*BatchResult, error)
        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificateBatch',
            contractArguments: [JSON.stringify(batch)],
            readOnly:          false,
            timeout:           120   // seconds — handles high-load orderer delays
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No resources to release
    }
}

module.exports = {
    createWorkloadModule: () => new IssueCertificateBatchWorkload()
};
