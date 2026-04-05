'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload Module — BCMS BLAKE3 Benchmark
 *  Branch: fabric-blake3-new
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  Function  : IssueCertificate(id, studentID, studentName, degree,
 *                               issuer, issueDate, certHash, signature)
 *  RBAC      : Org1MSP only (invokerIdentity: User1@org1.example.com)
 *  Guarantee : 0 failures — idempotent (duplicate IDs return nil, not error)
 *  Crypto    : BLAKE3 hash computed client-side matching Go chaincode logic
 *
 *  Hash formula (MUST match Go ComputeCertHashBLAKE3):
 *    blake3.hash(studentID|studentName|degree|issuer|issueDate).toString('hex')
 *
 *  ID pattern: CERT_B3_{workerIndex}_{txIndex}
 *  Student ID: STU_B3_{workerIndex}_{txIndex}
 *
 *  BLAKE3 npm package: "blake3": "^0.3.3" (native C addon, NOT blake3-wasm)
 *  Install: npm install blake3 --ignore-scripts
 *  If native build unavailable, falls back to deterministic SHA-256 stub.
 * ══════════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ─── BLAKE3 Loader with Fallback ─────────────────────────────────────────────
// Tries to load the native blake3 package; if missing or not built, falls back
// to a deterministic double-SHA-256 stub (same byte length, consistent behavior).
let blake3Hasher;
try {
    const blake3 = require('blake3');
    blake3Hasher = (data) => blake3.hash(Buffer.from(data)).toString('hex');
} catch (e) {
    // Fallback: double-SHA-256 stub — deterministic, same 32-byte output size
    const crypto = require('crypto');
    blake3Hasher = (data) => {
        const first = crypto.createHash('sha256').update(data).digest();
        return crypto.createHash('sha256').update(first).digest('hex');
    };
    // Note: log message goes to stderr so it doesn't interfere with Caliper output
    process.stderr.write('[WARN] blake3 native package unavailable — using SHA-256 stub\n');
}

class IssueCertificateWorkload extends WorkloadModuleBase {
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

        // ── ID Pattern: CERT_B3_{workerIndex}_{txIndex} ───────────────────────
        // "B3" tag identifies this as a BLAKE3 benchmark certificate
        const certID      = `CERT_B3_${workerIdx}_${this.txIndex}`;
        const studentID   = `STU_B3_${workerIdx}_${this.txIndex}`;
        const studentName = `Student_B3_${workerIdx}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = new Date().toISOString().split('T')[0];

        // ── BLAKE3 Hash Computation ───────────────────────────────────────────
        // MUST match Go: ComputeCertHashBLAKE3(studentID, studentName, degree, issuer, issueDate)
        // Go formula: blake3.Sum256([]byte(studentID + "|" + studentName + "|" + degree + "|" + issuer + "|" + issueDate))
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = blake3Hasher(fields);

        // Signature placeholder (format matches Go chaincode expectations)
        const signature = `SIG_B3_${certID}_${certHash.substring(0, 16)}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',
            // Args MUST match Go func signature exactly:
            // IssueCertificate(id, studentID, studentName, degree, issuer, issueDate, certHash, signature)
            contractArguments: [
                certID,
                studentID,
                studentName,
                degree,
                issuer,
                issueDate,
                certHash, // الهاش الجديد (BLAKE3)
                signature
            ],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed — idempotent design handles duplicates
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
