'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractId = this.roundArguments.contractId || 'bcms-sha256';
        // OOM-FIX: track consecutive failures for exponential back-off.
        // When the peer is overwhelmed (gRPC queue full / recovering from high
        // TPS VerifyCertificate round) queries arrive faster than the peer can
        // handle them. A simple 500ms fixed retry still hammers an already-busy
        // peer. Exponential back-off reduces pressure during recovery periods.
        this._consecutiveFails = 0;
    }

    async submitTransaction() {
        const request = {
            contractId:        this.contractId,
            contractFunction:  'QueryAllCertificates',
            contractArguments: ['20', ''],
            readOnly:          true,
        };

        // Exponential back-off retry: up to 3 attempts
        //   attempt 1 → immediate
        //   attempt 2 → wait 500ms  (peer flushing its gRPC queue)
        //   attempt 3 → wait 2000ms (peer recovering memory / GC)
        const delays = [0, 500, 2000];
        let lastErr;
        for (let attempt = 0; attempt < 3; attempt++) {
            if (delays[attempt] > 0) {
                await new Promise(r => setTimeout(r, delays[attempt]));
            }
            try {
                const result = await this.sutAdapter.sendRequests(request);
                // Reset failure counter on success
                this._consecutiveFails = 0;
                return result;
            } catch (err) {
                lastErr = err;
            }
        }

        // All 3 attempts failed — count the failure and propagate
        this._consecutiveFails++;

        // OOM-FIX: If we have 5+ consecutive failures, the peer is likely dead.
        // Add an extra 5s pause to give it time to restart (Docker auto-restart
        // policy) before the next submitTransaction() call.
        if (this._consecutiveFails >= 5) {
            await new Promise(r => setTimeout(r, 5000));
            this._consecutiveFails = 0; // reset so we try a fresh burst
        }

        throw lastErr;
    }

    async cleanupWorkloadModule() { }
}

module.exports = { createWorkloadModule: () => new QueryAllCertificatesWorkload() };