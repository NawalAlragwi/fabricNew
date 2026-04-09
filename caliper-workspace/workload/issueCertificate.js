'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload Module — BCMS Benchmark (mirage-new branch)
 * ══════════════════════════════════════════════════════════════════════
 *  Chaincode function signature (MUST MATCH smartcontract_hybrid.go):
 *    IssueCertificate(id, studentID, studentName, degree, issuer,
 *                     issueDate, certHash, signature) error
 *
 *  ROOT CAUSE FIX: Previous version sent JSON_ARRAY as argument, but
 *  the chaincode expects 8 individual string arguments.  This caused
 *  100% failure on IssueCertificate, which in turn caused 0% success
 *  on RevokeCertificate (nothing to revoke) and GetCertificatesByStudent
 *  (no certs on ledger to query).
 *
 *  Hash formula (client-side SHA-256; server stores hybrid SHA-256 XOR BLAKE3):
 *    SHA256(studentID + "|" + studentName + "|" + degree + "|" + issuer + "|" + issueDate)
 *  Note: Server-side chaincode always recomputes the authoritative hybrid hash.
 *  The client-side hash is accepted but overwritten server-side with hybrid hash.
 *
 *  ID pattern: CERT_{workerIndex}_{txIndex}  (used by revokeCertificate.js)
 *  StudentID:  STU_{workerIndex}_{txIndex}   (used by getCertificatesByStudent.js)
 *
 *  FIX v4.2: Added missing `const crypto = require('crypto')` import.
 * ══════════════════════════════════════════════════════════════════════
 */
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
        const workerIdx = this.workerIndex || 0;

        const certID      = `CERT_${workerIdx}_${this.txIndex}`;
        const studentID   = `STU_${workerIdx}_${this.txIndex}`;
        const studentName = `Student_${workerIdx}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = new Date().toISOString().split('T')[0];

        // Client-side SHA-256 hash — chaincode server will overwrite with hybrid hash:
        //   ComputeHybridHash: SHA256(data) XOR BLAKE3(data)
        // Client sends SHA256 only; server replaces with sha256-xor-blake3.
        const fields    = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash  = crypto.createHash('sha256').update(fields).digest('hex');
        const signature = `SIG_${certID}_${certHash.substring(0, 16)}`;

        const request = {
            contractId:        'bcms-hybrid',
            contractFunction:  'IssueCertificate',
            // ── CRITICAL FIX: 8 individual string args, NOT a JSON array ──
            contractArguments: [certID, studentID, studentName, degree, issuer, issueDate, certHash, signature],
            readOnly:          false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
