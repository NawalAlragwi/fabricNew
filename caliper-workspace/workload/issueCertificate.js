'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
// تم استبدال crypto بمكتبة blake3 المتطورة
const blake3 = require('blake3'); 

/**
 * ══════════════════════════════════════════════════════════════════════
 * IssueCertificate Workload Module — BCMS Benchmark (BLAKE3 Mode)
 * ══════════════════════════════════════════════════════════════════════
 * Crypto    : BLAKE3 hash computed client-side matching BLAKE3 chaincode
 * Parallel  : Supports hardware acceleration (SIMD) for faster hashing
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

        const workerIdx   = this.workerIndex || 0;
        const certID      = `CERT_B3_${workerIdx}_${this.txIndex}`;
        const studentID   = `STU_${workerIdx}_${this.txIndex}`;
        const studentName = `Student_${workerIdx}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = new Date().toISOString().split('T')[0];

        // BLAKE3 H(C) = BLAKE3(studentID | studentName | degree | issuer | issueDate)
        // يجب أن يطابق تماماً دالة ComputeCertHash() في عقد Go المحدث
        const fields   = [studentID, studentName, degree, issuer, issueDate].join('|');
        
        // حساب هاش BLAKE3 (بصيغة Hex)
        const certHash = blake3.hash(fields).toString('hex');
        
        const signature = `SIG_B3_${certID}_${certHash.substring(0, 16)}`;

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
                certHash, // الهاش الجديد (BLAKE3)
                signature
            ],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // No cleanup needed
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
