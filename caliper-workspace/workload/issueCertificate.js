'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        // نحدد حجم الدفعة (مثلاً 10 شهادات في كل معاملة)
        this.batchSize = 10; 
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
    }

    async submitTransaction() {
        let batch = [];
        const workerIdx = this.workerIndex || 0;

        // إنشاء مجموعة من الشهادات (Batch)
        for (let i = 0; i < this.batchSize; i++) {
            this.txIndex++;
            const certID = `CERT_${workerIdx}_${this.txIndex}`;
            const studentID = `STU_${workerIdx}_${this.txIndex}`;
            const studentName = `Student_${workerIdx}_${this.txIndex}`;
            const degree = 'Bachelor of Computer Science';
            const issuer = 'Digital University';
            const issueDate = new Date().toISOString().split('T')[0];

            // ملاحظة: الهاش الهجين يتم حسابه الآن داخل الـ Chaincode لضمان الدقة
            // لذا سنرسل البيانات الخام، أو هاش مبدئي.
            const fields = [studentID, studentName, degree, issuer, issueDate].join('|');
            const certHash = crypto.createHash('sha256').update(fields).digest('hex');
            const signature = `SIG_${certID}_${certHash.substring(0, 16)}`;

            batch.push({
                ID: certID,
                StudentID: studentID,
                StudentName: studentName,
                Degree: degree,
                Issuer: issuer,
                IssueDate: issueDate,
                CertHash: certHash,
                Signature: signature
            });
        }

        const request = {
            contractId: 'basic',
            contractFunction: 'IssueCertificate', // حافظنا على نفس الاسم
            contractArguments: [JSON.stringify(batch)], // نرسل المصفوفة كـ JSON String
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
