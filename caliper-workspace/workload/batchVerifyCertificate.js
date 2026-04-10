'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  BatchVerifyCertificate Workload — BCMS Hyper-Pach Benchmark
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target function: VerifyCertificate(certId, certHash)
 *  Access:          readOnly = true  (evaluate-only, bypasses orderer)
 *
 *  This workload verifies certificates that were previously issued by the
 *  BatchIssueCertificates round.  It targets HPACH_* certificates so that
 *  it only queries certs created in the hyper-pach scenario.
 *
 *  ── Rate ─────────────────────────────────────────────────────────────
 *  Fixed 1000 TPS for 30s
 *
 *  ── Hash Generation ──────────────────────────────────────────────────
 *  Recomputes SHA-256(studentId|name|degree|issuer|date) locally to
 *  match the on-chain hash computed by BatchIssueCertificates.
 * ══════════════════════════════════════════════════════════════════════════
 */
class BatchVerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        this.issueDate = new Date().toISOString().split('T')[0];
    }

    async submitTransaction() {
        this.txIndex++;
        const w = this.workerIndex || 0;

        // Target a cert from a prior BatchIssueCertificates call
        const certID      = `HPACH_${w}_${this.txIndex}_0`;
        const studentID   = `HSTU_${w}_${this.txIndex}_0`;
        const studentName = `HyperPachStudent_${w}_${this.txIndex}_0`;
        const degree      = 'Bachelor of Blockchain Engineering';
        const issuer      = 'HyperPach University';
        const issueDate   = this.issueDate;

        // Recompute the expected certHash (same formula as chaincode ComputeHybridHash)
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = crypto.createHash('sha256').update(fields).digest('hex');

        return this.sutAdapter.sendRequests({
            contractId:        'bcms-hybrid',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true,
        });
    }

    async cleanupWorkloadModule() {
        // No cleanup required
    }
}

function createWorkloadModule() {
    return new BatchVerifyCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
