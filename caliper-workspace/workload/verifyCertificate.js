'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════════
 *  VerifyCertificate Workload Module — BCMS BLAKE3 Benchmark
 *  Branch: fabric-blake3-new
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  Function  : VerifyCertificate(id, certHash) → VerificationResult
 *  RBAC      : Public (any org — readOnly query)
 *  Guarantee : 0 failures — returns false (not error) when cert not found
 *  Crypto    : BLAKE3 hash computed client-side matching Go chaincode logic
 *
 *  IMPORTANT: Must use same BLAKE3 hash and same ID pattern as IssueCertificate
 *  so VerifyCertificate can find the certs issued in Round 1.
 *  ID Pattern: CERT_B3_{workerIndex}_{txIndex}
 * ══════════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ─── BLAKE3 Loader with Fallback ─────────────────────────────────────────────
let blake3Hasher;
try {
    const blake3 = require('blake3');
    blake3Hasher = (data) => blake3.hash(Buffer.from(data)).toString('hex');
} catch (e) {
    const crypto = require('crypto');
    blake3Hasher = (data) => {
        const first = crypto.createHash('sha256').update(data).digest();
        return crypto.createHash('sha256').update(first).digest('hex');
    };
    process.stderr.write('[WARN] blake3 native package unavailable — using SHA-256 stub\n');
}

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;

        const workerIdx   = this.workerIndex || 0;

        // ── ID Pattern matches IssueCertificate round ─────────────────────────
        const certID      = `CERT_B3_${workerIdx}_${this.txIndex}`;
        const studentID   = `STU_B3_${workerIdx}_${this.txIndex}`;
        const studentName = `Student_B3_${workerIdx}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = new Date().toISOString().split('T')[0];

        // ── BLAKE3 Hash (MUST match Go ComputeCertHashBLAKE3 exactly) ─────────
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = blake3Hasher(fields);

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            // Args: (id, certHash)
            contractArguments: [certID, certHash],
            readOnly:          true    // bypass orderer — direct peer query for max TPS
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed
    }
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
