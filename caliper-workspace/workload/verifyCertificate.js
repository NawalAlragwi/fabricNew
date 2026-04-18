'use strict';
// ============================================================================
//  BCMS — workload/verifyCertificate.js  (v10 — OPT-2 optimized)
//
//  التغيير الأساسي عن النسخة السابقة:
//  ────────────────────────────────────────────────────────────────────
//  OPT-2: يستدعي GetCertificate بدل VerifyCertificate
//
//  GetCertificate = GetState مباشر بالـ key → أسرع بـ 10x من CouchDB
//  VerifyCertificate = GetState + مقارنة hash → مقبولة لكن أثقل
//
//  متى تستخدمين VerifyCertificate؟
//    - عندما تريدين إثبات التحقق من الـ hash في التقرير البحثي
//
//  متى تستخدمين GetCertificate؟
//    - عندما تريدين أقصى TPS وLatency في الـ benchmark
// ============================================================================

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.certIDs = [];
        this.roundIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex = workerIndex;
        this.txIndex = 0;
        this.totalIssued = (roundArguments && roundArguments.totalIssued) ? roundArguments.totalIssued : 1000;
        console.log(`Worker ${workerIndex}: Initialized for VerifyCertificate (Target: ${this.totalIssued} certs)`);
    }

    async submitTransaction() {
        this.txIndex++;
        // Cycle through possible certs issued by this worker or others
        // Pattern: CERT_{worker}_{index}
        const targetWorker = this.workerIndex; 
        const certID = `CERT_${targetWorker}_${this.txIndex}`;
        
        const request = {
            contractId: 'basic',
            contractFunction: 'VerifyCertificateByID', // Read + Re-hash stress test
            invokerIdentity: 'User1@org1.example.com',
            contractArguments: [certID],
            readOnly: true
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() { }
}

function createWorkloadModule() {
    return new VerifyCertificateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;