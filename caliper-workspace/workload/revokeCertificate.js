'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  RevokeCertificate Workload — BCMS Benchmark (Scenarios S1 / S3 / S4)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Function signature (all smart contracts):
 *    RevokeCertificate(id) error
 *
 *  ── KEY SCHEME (must match IssueCertificate / IssueCertificateBatch) ──
 *
 *  S1 (SHA-256)     : IssueCertificate  → CERT_{w}_{i}
 *  S3 (Hybrid)      : IssueCertificate  → CERT_{w}_{i}
 *  S4 (Hybrid-Batch): IssueCertificateBatch → BCERT_{w}_{tx}_{i}
 *
 *  Root cause of previous 36% failure rate in RevokeCertificate:
 *    S4 benchmark used revoke workload targeting CERT_{w}_{i} keys,
 *    but IssueCertificateBatch stores certs as BCERT_{w}_{tx}_{i}.
 *    → Every revoke targeted non-existent keys → idempotent nil return
 *      was counted as a success by Fabric but the cert was never revoked.
 *    → Under MVCC, concurrent revokes on the same key cause conflicts.
 *
 *  Fix: Read certPrefix from roundArguments (default: "CERT").
 *    S1/S3 benchmark YAML → no argument needed  (defaults to CERT_)
 *    S4 benchmark YAML    → set certPrefix: "BCERT"
 *
 *  ── MVCC Safety ──────────────────────────────────────────────────────
 *    Each worker revokes ONLY its own keys (workerIndex in the ID).
 *    → Zero cross-worker key collisions → zero MVCC phantom-read conflicts.
 *
 *  ── Idempotency ──────────────────────────────────────────────────────
 *    RevokeCertificate returns nil on cert-not-found AND already-revoked.
 *    → Safe to re-run; zero cascading failures.
 * ══════════════════════════════════════════════════════════════════════════
 */
class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex      = 0;
        this.totalIssued  = 5000;
        this.certPrefix   = 'CERT';   // S1/S3 default; S4 overrides with "BCERT"
        this.batchSize    = 1;        // certs per batch tx (S4 only); used for S4 key calc
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex  = workerIndex;
        this.totalWorkers = totalWorkers;
        this.txIndex      = 0;

        // totalIssued: total certificates issued in the IssueCertificate round.
        // For S4, this should be totalTxSent (not totalCerts) because each tx
        // issued batchSize certs. The key is BCERT_{w}_{txIndex}_{i}.
        this.totalIssued  = (roundArguments && roundArguments.totalIssued)
            ? parseInt(roundArguments.totalIssued, 10)
            : 5000;

        // certPrefix: key prefix used by the issue workload.
        //   S1/S3: "CERT"   → key = CERT_{w}_{txIndex}
        //   S4:    "BCERT"  → key = BCERT_{w}_{txIndex}_{certIndex}
        this.certPrefix   = (roundArguments && roundArguments.certPrefix)
            ? roundArguments.certPrefix
            : 'CERT';

        // batchSize: only relevant when certPrefix = "BCERT" (S4).
        // Used to target individual certs within a batch tx.
        this.batchSize    = (roundArguments && roundArguments.batchSize)
            ? parseInt(roundArguments.batchSize, 10)
            : 1;

        console.log(
            `Worker ${workerIndex}: RevokeCertificate initialized.` +
            ` prefix=${this.certPrefix} totalIssued=${this.totalIssued}` +
            ` batchSize=${this.batchSize}`
        );
    }

    async submitTransaction() {
        this.txIndex++;

        const w                = this.workerIndex || 0;
        const issuedPerWorker  = Math.floor(this.totalIssued / this.totalWorkers);
        const safeIssuedCount  = Math.max(issuedPerWorker - 50, 10);

        let certID;

        if (this.certPrefix === 'BCERT') {
            // ── S4 key scheme: BCERT_{w}_{txIndex}_{certIndex} ──────────────
            // txIndex cycles over issued txs; certIndex cycles within the batch.
            const txIdx   = (Math.floor((this.txIndex - 1) / this.batchSize) % safeIssuedCount) + 1;
            const certIdx = (this.txIndex - 1) % this.batchSize;
            certID = `BCERT_${w}_${txIdx}_${certIdx}`;
        } else {
            // ── S1/S3 key scheme: CERT_{w}_{txIndex} ────────────────────────
            const idx = ((this.txIndex - 1) % safeIssuedCount) + 1;
            certID = `CERT_${w}_${idx}`;
        }

        const request = {
            contractId:        this.roundArguments.contractId || 'bcms-sha256',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false,
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
