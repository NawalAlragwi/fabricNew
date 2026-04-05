'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ══════════════════════════════════════════════════════════════════════════════
//  VerifyCertificate Workload — BCMS BLAKE3 Benchmark
//  Branch: fabric-blake3
//
//  Migration: SHA-256 → BLAKE3
//    Hash recomputed client-side with blake3 npm package.
//    Must produce output identical to Go chaincode for hash-match verification.
//
//  ID pattern: CERT_B3_{workerIndex}_{txIndex}
//    Matches IssueCertificate workload → verifies certs issued in Round 1.
//
//  readOnly: true — direct peer query, bypasses orderer for max TPS.
//  Zero-failure design: VerifyCertificate returns VerificationResult{valid:false}
//  (not Go error) when cert not found — Caliper counts as SUCCESS.
//
//  Function signature (smartcontract_blake3.go):
//    VerifyCertificate(id, certHash) (*VerificationResult, error)
// ══════════════════════════════════════════════════════════════════════════════

// ── BLAKE3 library bootstrap ──────────────────────────────────────────────────
let blake3Lib = null;

function loadBlake3() {
    if (blake3Lib !== null) return blake3Lib;
    try {
        blake3Lib = require('blake3');
        return blake3Lib;
    } catch (_) {
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
 * MUST match ComputeCertHashBLAKE3() in smartcontract_blake3.go exactly.
 */
function computeBlake3Hash(studentID, studentName, degree, issuer, issueDate) {
    const b3 = loadBlake3();
    const data = [studentID, studentName, degree, issuer, issueDate].join('|');
    const hashBytes = b3.hash(Buffer.from(data, 'utf8'));
    return Buffer.from(hashBytes).toString('hex');
}

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        // Use today's date — same as issueCertificate so BLAKE3 hashes match
        this.issueDate = new Date().toISOString().split('T')[0];
    }

    async submitTransaction() {
        this.txIndex++;

        const w           = this.workerIndex || 0;
        const certID      = `CERT_B3_${w}_${this.txIndex}`;
        const studentID   = `STU_${w}_${this.txIndex}`;
        const studentName = `Student_${w}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = this.issueDate;

        // Recompute BLAKE3 — must match IssueCertificate hash exactly
        const certHash = computeBlake3Hash(studentID, studentName, degree, issuer, issueDate);

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            // Args: (id, certHash)
            contractArguments: [certID, certHash],
            readOnly:          true, // bypass orderer — direct peer query for max TPS
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
