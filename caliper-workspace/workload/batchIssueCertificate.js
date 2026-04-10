'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  BatchIssueCertificate Workload — BCMS Hyper-Pach Benchmark
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target function: BatchIssueCertificates(batchId, certsJSON)
 *
 *  Key differences vs IssueCertificateBatch:
 *    - batchSize default: 5 (smaller batches → lower latency per tx)
 *    - Uses CertificateBatchRequest struct (no certHash in input — computed on-chain)
 *    - Partial-failure semantics: failures in one cert don't abort the batch
 *    - Returns BatchResult JSON with processed/succeeded/failed/failedIds
 *
 *  ── MVCC Safety ──────────────────────────────────────────────────────
 *  Each cert has a unique ID: HPACH_{worker}_{txIndex}_{i}
 *  → No two workers share a key → zero MVCC phantom-read conflicts.
 *
 *  ── Hybrid Crypto ────────────────────────────────────────────────────
 *  blake3Hash = SHA-256(studentId|...) as placeholder for off-chain BLAKE3
 *  certHash   = computed ON-CHAIN by BatchIssueCertificates (not sent)
 *
 *  ── Performance Design ───────────────────────────────────────────────
 *  batchSize=5, tps=20 → ~100 certificates/second
 *  Effective certs/s = Caliper TPS × batchSize
 * ══════════════════════════════════════════════════════════════════════════
 */
class BatchIssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.batchSize = 5;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        this.batchSize = (roundArguments && roundArguments.batchSize)
            ? parseInt(roundArguments.batchSize, 10)
            : 5;
        this.issueDate = new Date().toISOString().split('T')[0];
    }

    async submitTransaction() {
        this.txIndex++;
        const w       = this.workerIndex || 0;
        const batchId = `HPACH_W${w}_TX${this.txIndex}_${Date.now()}`;

        // Build batch using CertificateBatchRequest schema
        // Note: no certHash field — it is computed on-chain by BatchIssueCertificates
        const certs = [];
        for (let i = 0; i < this.batchSize; i++) {
            const certID      = `HPACH_${w}_${this.txIndex}_${i}`;
            const studentID   = `HSTU_${w}_${this.txIndex}_${i}`;
            const studentName = `HyperPachStudent_${w}_${this.txIndex}_${i}`;
            const degree      = 'Bachelor of Blockchain Engineering';
            const issuer      = 'HyperPach University';
            const issueDate   = this.issueDate;

            // Generate signature via SHA-256 (worker-aware, unique per cert)
            const sigData  = `${certID}|${studentID}|${degree}|${issuer}|${issueDate}|${w}`;
            const signature = crypto.createHash('sha256').update(sigData).digest('hex');

            // BLAKE3 placeholder: SHA-256 of the concatenated fields (advisory only)
            const fields     = [studentID, studentName, degree, issuer, issueDate].join('|');
            const blake3Hash = crypto.createHash('sha256').update(fields).digest('hex');

            certs.push({
                id:          certID,
                studentId:   studentID,
                studentName: studentName,
                degree:      degree,
                issuer:      issuer,
                issueDate:   issueDate,
                signature:   signature,
                blake3Hash:  blake3Hash,
            });
        }

        return this.sutAdapter.sendRequests({
            contractId:        'bcms-hybrid',
            contractFunction:  'BatchIssueCertificates',
            contractArguments: [batchId, JSON.stringify(certs)],
            readOnly:          false,
        });
    }

    async cleanupWorkloadModule() {
        // No cleanup required
    }
}

function createWorkloadModule() {
    return new BatchIssueCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
