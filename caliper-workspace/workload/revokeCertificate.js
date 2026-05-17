'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  RevokeCertificate Workload — BCMS Benchmark (Scenarios S1 / S3 / S4)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  OOM-FIX (v15): Added exponential back-off retry for gRPC errors.
 *  When the peer is recovering from peak-TPS VerifyCertificate load,
 *  immediate retry floods an already-busy peer and prolongs recovery.
 *  Back-off: 0ms → 800ms → 3000ms (3 total attempts).
 *  If 5+ consecutive failures occur, insert extra 5s peer-recovery pause.
 *
 *  KEY SCHEME (unchanged):
 *    S1/S3: CERT_{w}_{txIndex}
 *    S4:    BCERT_{w}_{txIndex}_{certIndex}
 * ══════════════════════════════════════════════════════════════════════════
 */
class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex           = 0;
        this.totalIssued       = 5000;
        this.certPrefix        = 'CERT';
        this.batchSize         = 1;
        this._consecutiveFails = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex  = workerIndex;
        this.totalWorkers = totalWorkers;
        this.txIndex      = 0;
        this._consecutiveFails = 0;

        this.totalIssued = (roundArguments && roundArguments.totalIssued)
            ? parseInt(roundArguments.totalIssued, 10)
            : 5000;

        this.certPrefix = (roundArguments && roundArguments.certPrefix)
            ? roundArguments.certPrefix
            : 'CERT';

        this.batchSize = (roundArguments && roundArguments.batchSize)
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

        const w               = this.workerIndex || 0;
        const issuedPerWorker = Math.floor(this.totalIssued / this.totalWorkers);
        const safeIssuedCount = Math.max(issuedPerWorker - 50, 10);

        let certID;
        if (this.certPrefix === 'BCERT') {
            const txIdx   = (Math.floor((this.txIndex - 1) / this.batchSize) % safeIssuedCount) + 1;
            const certIdx = (this.txIndex - 1) % this.batchSize;
            certID = `BCERT_${w}_${txIdx}_${certIdx}`;
        } else {
            const idx = ((this.txIndex - 1) % safeIssuedCount) + 1;
            certID = `CERT_${w}_${idx}`;
        }

        const request = {
            contractId:        this.roundArguments.contractId || 'bcms-sha256',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID],
            readOnly:          false,
        };

        // OOM-FIX: exponential back-off retry (write TX)
        // Delays: attempt 1=0ms, attempt 2=800ms, attempt 3=3000ms
        // Write TXs need slightly longer delays than reads because the
        // orderer also needs to recover from a high-TPS burst.
        const delays = [0, 800, 3000];
        let lastErr;
        for (let attempt = 0; attempt < 3; attempt++) {
            if (delays[attempt] > 0) {
                await new Promise(r => setTimeout(r, delays[attempt]));
            }
            try {
                const result = await this.sutAdapter.sendRequests(request);
                this._consecutiveFails = 0;
                return result;
            } catch (err) {
                lastErr = err;
            }
        }

        this._consecutiveFails++;
        if (this._consecutiveFails >= 5) {
            await new Promise(r => setTimeout(r, 5000));
            this._consecutiveFails = 0;
        }
        throw lastErr;
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new RevokeCertificateWorkload() };
