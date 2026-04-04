'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

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
        
        // توليد معرفات فريدة باستخدام رقم العامل (Worker) والفهرس لضمان عدم التكرار (Primary Key)
        // هذا يضمن 0% Failure Rate بسبب الـ "Keys Collisions"
        const workerIdx = this.workerIndex || 0;
        const certID = `CERT_${workerIdx}_${this.txIndex}_${Date.now()}`;
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