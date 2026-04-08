'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * ══════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload Module — BCMS Benchmark (mirage branch)
 * ══════════════════════════════════════════════════════════════════════
 *  Chaincode function signature (MUST MATCH smartcontract.go):
 *    IssueCertificate(id, studentID, studentName, degree, issuer,
 *                     issueDate, certHash, signature) error
 *
 *  Hash: Hybrid SHA-256 XOR BLAKE3
 *    - certHash is left EMPTY so the chaincode computes the hybrid hash
 *      server-side using ComputeHybridHash(). This avoids needing a
 *      BLAKE3 implementation in the Node.js workload.
 *    - The chaincode is idempotent: duplicate ID → nil, not error.
 *
 *  ID pattern: CERT_{workerIndex}_{txIndex}  (used by revokeCertificate.js)
 *  StudentID:  STU_{workerIndex}_{txIndex}   (used by getCertificatesByStudent.js)
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
        
        // توليد معرفات فريدة وقابلة للاسترجاع في جولة RevokeCertificate لاحقاً
        // يجب أن يكون معرف الشهادة نفسه مستخدماً في كلتا الجولتين لكي يتم العثور عليها بنجاح.
        const workerIdx = this.workerIndex || 0;
        const certID = `CERT_${workerIdx}_${this.txIndex}`;
        const studentID = `STU_${workerIdx}_${this.txIndex}`;
        const studentName = `Student Name ${workerIdx}_${this.txIndex}`;
        const degree = 'Bachelor of Computer Science';
        const issuer = 'Digital University';
        const issueDate = new Date().toISOString().split('T')[0];
        
        // سنترك العقد الذكي يحسب الهاش الهجين داخلياً لضمان دقة البحث
        const certHash = ""; 
        const signature = `SIG_${certID}`;

        const request = {
            contractId: 'basic',
            contractFunction: 'IssueCertificate',
            // إرسال المتغيرات الثمانية كعناصر مستقلة في المصفوفة كما يتوقعها العقد الذكي (Individual)
            contractArguments: [
                certID, 
                studentID, 
                studentName, 
                degree, 
                issuer, 
                issueDate, 
                certHash, 
                signature
            ],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // لا يوجد ملفات مؤقتة للمسح
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };