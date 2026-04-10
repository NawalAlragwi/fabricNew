'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  BatchRevokeCertificate Workload — BCMS Hyper-Pach Benchmark
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target function: RevokeCertificate(certId, reason)
 *  Caller MSP:      Org2MSP (RBAC enforcement in chaincode)
 *
 *  This workload revokes certificates that were previously issued by the
 *  BatchIssueCertificates round.  It targets HPACH_* certificates so that
 *  it only touches certs created in the hyper-pach scenario.
 *
 *  ── Rate ─────────────────────────────────────────────────────────────
 *  Fixed 1000 TPS for 30s (read-write mix typical in BCMS deployment)
 *
 *  ── MVCC Safety ──────────────────────────────────────────────────────
 *  Each call revokes a distinct cert ID derived from workerIndex + txIndex
 *  so no two concurrent workers touch the same key.
 * ══════════════════════════════════════════════════════════════════════════
 */
class BatchRevokeCertificateWorkload extends WorkloadModuleBase {
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
        const w      = this.workerIndex || 0;
        // Target certs that would have been issued in prior rounds.
        // We use txIndex modulo a large-enough range to spread evenly.
        const certID = `HPACH_${w}_${this.txIndex}_0`; // first cert in each batch

        return this.sutAdapter.sendRequests({
            contractId:        'bcms-hybrid',
            contractFunction:  'RevokeCertificate',
            contractArguments: [certID, 'Hyper-Pach batch revocation test'],
            readOnly:          false,
        });
    }

    async cleanupWorkloadModule() {
        // No cleanup required
    }
}

function createWorkloadModule() {
    return new BatchRevokeCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
