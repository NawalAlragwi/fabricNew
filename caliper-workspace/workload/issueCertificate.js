'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload — BCMS BLAKE3 Benchmark  (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ─── BLAKE3 Loader with Fallback ─────────────────────────────────────────────
let blake3Hasher;
try {
    const blake3 = require('blake3');
    blake3Hasher = (data) => blake3.hash(Buffer.from(data)).toString('hex');
    process.stderr.write('[INFO] blake3 native package loaded successfully\n');
} catch (e) {
    // Fallback: double-SHA-256 stub — deterministic, same 32-byte output size
    const crypto = require('crypto');
    blake3Hasher = (data) => {
        const first = crypto.createHash('sha256').update(data).digest();
        return crypto.createHash('sha256').update(first).digest('hex');
    };
    process.stderr.write('[WARN] blake3 native package unavailable — using SHA-256 stub\n');
}

class IssueCertificateWorkload extends WorkloadModuleBase {
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

        const w           = this.workerIndex || 0;
        const certID      = `CERT_${w}_${this.txIndex}`;
        const studentID   = `STU_${w}_${this.txIndex}`;
        const studentName = `Student_${w}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = this.issueDate;

        // ✅ الإصلاح: استخدام blake3Hasher بدل crypto.createHash مباشرة
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = blake3Hasher(fields);

        const signature = `SIG_${certID}_${certHash.substring(0, 16)}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',
            contractArguments: [
                certID,
                studentID,
                studentName,
                degree,
                issuer,
                issueDate,
                certHash,
                signature,
            ],
            readOnly: false,
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };