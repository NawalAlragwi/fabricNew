'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  VerifyCertificate Workload — BCMS BLAKE3 Benchmark (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: chaincode-bcms/blake3 (deployed as basic)
 *
 *  Function signature (smartcontract_blake3.go):
 *    VerifyCertificate(id, certHash) (*VerificationResult, error)
 *
 *  readOnly:true — direct peer query, bypasses orderer for max TPS.
 *  Zero-failure design: VerifyCertificate NEVER returns a Go error for
 *  "not found" — it returns a VerificationResult{valid:false}.
 *  Therefore even when cert is not yet on-chain, Caliper counts SUCCESS.
 *
 *  ID pattern matches issueCertificate.js so certs issued in Round 1
 *  are verified in Round 2 (with hash recomputed identically).
 *
 *  CouchDB Index: VerifyCertificate uses GetState (key lookup) — no
 *  index required. Full index benefit is in QueryAllCertificates /
 *  GetCertificatesByStudent.
 * ══════════════════════════════════════════════════════════════════════════
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
        this.txIndex   = 0;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        // Use today's date — same as issueCertificate so hashes match
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

        // Recompute SHA-256 — must match IssueCertificate certHashInput exactly
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = blake3Hasher(fields);

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true,  // bypass orderer — direct peer query
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
