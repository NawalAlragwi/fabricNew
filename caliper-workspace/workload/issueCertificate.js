'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        // نحدد حجم الدفعة (مثلاً 5 شهادات في كل معاملة بلوكشين)
        // يمكنك تغيير هذا الرقم لاختبار تأثير حجم الدفعة على الأداء
        this.batchSize = 5; 
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
    }

    async submitTransaction() {
        let batch = [];
        const workerIdx = this.workerIndex || 0;

        // ─── إنشاء الدفعة (Batch Generation) ───
        for (let i = 0; i < this.batchSize; i++) {
            this.txIndex++;
            const certID = `CERT_${workerIdx}_${this.txIndex}_${Date.now()}`;
            const studentID = `STU_${workerIdx}_${this.txIndex}`;
            const studentName = `Student Name ${this.txIndex}`;
            const degree = 'PhD in Computer Science'; // تيمناً ببحثك دكتور
            const issuer = 'Sana University';
            const issueDate = new Date().toISOString().split('T')[0];

            // ملاحظة: الهاش الهجين سيتم حسابه داخل الـ Chaincode لضمان النزاهة
            // نحن هنا نرسل البيانات الأساسية المطلوبة لهيكل Certificate في Go
            batch.push({
                id: certID,
                student_id: studentID,
                student_name: studentName,
                degree: degree,
                issuer: issuer,
                issue_date: issueDate,
                is_revoked: false
            });
        }

        const request = {
            contractId: 'basic', 
            // تم التعديل ليتطابق مع اسم الدالة في العقد الذكي الهجين
            contractFunction: 'IssueCertificateBatch', 
            // تحويل المصفوفة إلى String لأن العقد الذكي يستقبل JSON string
            contractArguments: [JSON.stringify(batch)], 
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // تنظيف الموارد إذا لزم الأمر
    }
}

function createWorkloadModule() {
    return new IssueCertificateWorkload();
}

module.exports = { createWorkloadModule };