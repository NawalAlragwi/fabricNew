'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * HashOnlyBenchmark — pure CPU hash isolation workload.
 *
 * OOM-FIX (v15): Added exponential back-off retry.
 * This is a READ-ONLY transaction (readOnly: true), so it only touches
 * the peer's query path — no orderer involved. Back-off delays are short:
 *   attempt 1 → 0ms  (immediate)
 *   attempt 2 → 300ms
 *   attempt 3 → 1500ms
 * If 5+ consecutive failures occur, insert a 5s pause to allow peer restart.
 *
 * The payload is pre-built once in initializeWorkloadModule() to avoid
 * per-TX string allocation overhead at high TPS.
 */
class HashOnlyBenchmarkWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex           = 0;
        this.payloadSize       = 20000;
        this._payload          = null;
        this._consecutiveFails = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex           = 0;
        this._consecutiveFails = 0;

        this.payloadSize = (roundArguments && roundArguments.payloadSize)
            ? parseInt(roundArguments.payloadSize, 10)
            : 20000;

        // Pre-build payload once — avoids repeated 20KB string allocation per TX
        this._payload = 'X'.repeat(this.payloadSize);
    }

    async submitTransaction() {
        this.txIndex++;

        const request = {
            contractId:        this.roundArguments.contractId || 'bcms-sha256',
            contractFunction:  'HashOnlyBenchmark',
            invokerIdentity:   'User1@org1.example.com',
            contractArguments: [this._payload],
            readOnly:          true,
        };

        // OOM-FIX: exponential back-off for read failures after peer OOM
        const delays = [0, 300, 1500];
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

    async cleanupWorkloadModule() { }
}

module.exports = { createWorkloadModule: () => new HashOnlyBenchmarkWorkload() };
