'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  IssueCertificateBatch Workload — BCMS Hybrid-Batch Benchmark
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target function: IssueCertificateBatch(batchId, certsJSON)
 *
 *  This workload sends multiple certificates in a SINGLE transaction.
 *  Configurable batch size via roundArguments.batchSize (default: 10).
 *
 *  ── MVCC Safety ──────────────────────────────────────────────────────
 *  Each cert in the batch has a unique ID: BCERT_{worker}_{txIndex}_{i}
 *  → No two workers share a key → zero MVCC phantom-read conflicts.
 *
 *  ── Hybrid Crypto ────────────────────────────────────────────────────
 *  certHash   = SHA-256(studentId|name|degree|issuer|date)   ← primary
 *  blake3Hash = SHA-256(certHash) as BLAKE3 placeholder      ← advisory
 *
 *  ── Performance Design ───────────────────────────────────────────────
 *  Sending N certs per tx reduces the number of orderer round-trips by N×.
 *  This dramatically improves effective throughput for write workloads.
 *  Recommended batch sizes: 5–50 for Fabric test-network.
 * ══════════════════════════════════════════════════════════════════════════
 */
class IssueCertificateBatchWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.batchSize = 10;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        this.batchSize = (roundArguments && roundArguments.batchSize) ? parseInt(roundArguments.batchSize, 10) : 10;
        this.issueDate = new Date().toISOString().split('T')[0];
    }

    async submitTransaction() {
        this.txIndex++;
        const w       = this.workerIndex || 0;
        const batchId = `BCERT_W${w}_TX${this.txIndex}_${Date.now()}`;

        // Build batch of certificates
        const certs = [];
        for (let i = 0; i < this.batchSize; i++) {
            const certID      = `BCERT_${w}_${this.txIndex}_${i}`;
            const studentID   = `BSTU_${w}_${this.txIndex}_${i}`;
            const studentName = `BatchStudent_${w}_${this.txIndex}_${i}`;
            const degree      = 'Bachelor of Computer Science';
            const issuer      = 'Digital University';
            const issueDate   = this.issueDate;

            const fields     = [studentID, studentName, degree, issuer, issueDate].join('|');
            const certHash   = crypto.createHash('sha256').update(fields).digest('hex');
            const blake3Hash = crypto.createHash('sha256').update(certHash).digest('hex');
            const signature  = `SIG_${certID}_${certHash.substring(0, 16)}`;

            certs.push({
                id:          certID,
                studentId:   studentID,
                studentName: studentName,
                degree:      degree,
                issuer:      issuer,
                issueDate:   issueDate,
                certHash:    certHash,
                blake3Hash:  blake3Hash,
                signature:   signature,
            });
        }

        return this.sutAdapter.sendRequests({
            contractId:        this.roundArguments.contractId || 'bcms-hybrid-batch',
            contractFunction:  'IssueCertificateBatch',
            contractArguments: [batchId, JSON.stringify(certs)],
            readOnly:          false,
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new IssueCertificateBatchWorkload() };
