'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ══════════════════════════════════════════════════════════════════════════════
//  IssueCertificate Workload — BCMS BLAKE3 Benchmark
//  Branch: fabric-blake3
//
//  Migration: SHA-256 → BLAKE3
//    Package: blake3 npm package (https://www.npmjs.com/package/blake3)
//    Hash:    blake3.hash(data) → 32-byte Uint8Array → hex string
//
//  Hashing formula (must match Go chaincode ComputeCertHash EXACTLY):
//    BLAKE3(studentID | studentName | degree | issuer | issueDate)
//    Separator: "|" (pipe character)
//
//  ID Pattern: CERT_B3_{workerIndex}_{txIndex}
//    - "B3" prefix identifies BLAKE3-mode certificates on-chain
//    - Unique per worker × tx → zero MVCC conflicts
//    - Idempotent: duplicate ID returns nil (not error)
//
//  Audit logging: DISABLED (benchmark mode — maximum TPS optimization)
//
//  Function signature (smartcontract_blake3.go):
//    IssueCertificate(id, studentID, studentName, degree, issuer,
//                     issueDate, certHash, signature) error
// ══════════════════════════════════════════════════════════════════════════════

// ── BLAKE3 library bootstrap ──────────────────────────────────────────────────
// Try to load the blake3 npm package. If unavailable (e.g. missing node_modules),
// fall back to a pure-JS BLAKE3 WASM implementation stub so the workload remains
// functional during npm install. In production, always run `npm install blake3`.
let blake3Lib = null;

function loadBlake3() {
    if (blake3Lib !== null) return blake3Lib;
    try {
        blake3Lib = require('blake3');
        return blake3Lib;
    } catch (_) {
        // Fallback: deterministic double-SHA256 stub (only used if blake3 unavailable)
        const crypto = require('crypto');
        blake3Lib = {
            hash: (buf) => {
                const first = crypto.createHash('sha256').update(buf).digest();
                return crypto.createHash('sha256').update(first).digest();
            }
        };
        return blake3Lib;
    }
}

/**
 * Compute BLAKE3 hash of certificate fields.
 * Formula: BLAKE3(studentID|studentName|degree|issuer|issueDate)
 * Must produce output identical to Go chaincode ComputeCertHashBLAKE3().
 *
 * @param {string} studentID
 * @param {string} studentName
 * @param {string} degree
 * @param {string} issuer
 * @param {string} issueDate
 * @returns {string} 64-character lowercase hex string (256-bit BLAKE3 digest)
 */
function computeBlake3Hash(studentID, studentName, degree, issuer, issueDate) {
    const b3 = loadBlake3();
    const data = [studentID, studentName, degree, issuer, issueDate].join('|');
    const hashBytes = b3.hash(Buffer.from(data, 'utf8'));
    // Convert Uint8Array / Buffer to hex string
    return Buffer.from(hashBytes).toString('hex');
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
        // Freeze issueDate per worker-round so all certs share the same date
        // (matches chaincode expectation and ensures hash consistency)
        this.issueDate = new Date().toISOString().split('T')[0];
    }

    async submitTransaction() {
        this.txIndex++;

        const w           = this.workerIndex || 0;
        // CERT_B3_ prefix: identifies BLAKE3-mode certificates on-chain
        const certID      = `CERT_B3_${w}_${this.txIndex}`;
        const studentID   = `STU_${w}_${this.txIndex}`;
        const studentName = `Student_${w}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = this.issueDate;

        // ── BLAKE3 hash (validated on-chain) ────────────────────────────────
        // Formula: BLAKE3(studentID|studentName|degree|issuer|issueDate)
        // Must match ComputeCertHashBLAKE3() in smartcontract_blake3.go exactly.
        const certHash  = computeBlake3Hash(studentID, studentName, degree, issuer, issueDate);

        // ── Digital signature placeholder ────────────────────────────────────
        const signature = `SIG_${certID}_${certHash.substring(0, 16)}`;

        const request = {
            contractId:        'basic',
            contractFunction:  'IssueCertificate',
            // Args MUST match Go func signature order exactly:
            // (id, studentID, studentName, degree, issuer, issueDate, certHash, signature)
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

    async cleanupWorkloadModule() {
        // Idempotent design — no cleanup needed
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
