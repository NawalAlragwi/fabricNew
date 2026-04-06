'use strict';

/**
 * ══════════════════════════════════════════════════════════════════════════
 * VerifyCertificate Workload — BCMS BLAKE3 Benchmark (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

// ─── BLAKE3 Loader with Fallback (Must match IssueCertificate logic) ────────
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
}

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
        this.issueDate = new Date().toISOString().split('T')[0];
    }

    async submitTransaction() {
        this.txIndex++;

        const w = this.workerIndex || 0;
        const certID = `CERT_${w}_${this.txIndex}`;
        
        // الحقول المستخدمة في حساب الهاش (يجب أن تطابق ما تم إرساله في جولة الـ Issue)
        const studentID   = `STU_${w}_${this.txIndex}`;
        const studentName = `Student_${w}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = this.issueDate;

        // ✅ التحديث الجوهري: تجميع الحقول باستخدام الفاصل | ليتوافق مع العقد المحسن
        const fields = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash = blake3Hasher(fields);

        const request = {
            contractId:       'basic',
            contractFunction: 'VerifyCertificate',
            contractArguments: [
                certID,
                certHash, // إرسال الهاش المولد للمقارنة داخل العقد
            ],
            readOnly: true, // عمليات التحقق هي عمليات قراءة فقط لا تمر عبر الـ Orderer
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };