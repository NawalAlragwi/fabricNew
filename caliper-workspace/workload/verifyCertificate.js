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
        this.totalWorkers = totalWorkers;
        this.txIndex = 0;
        
        this.totalIssued = (roundArguments && roundArguments.totalIssued) ? parseInt(roundArguments.totalIssued, 10) : 1000;
        this.certPrefix  = (roundArguments && roundArguments.certPrefix) ? roundArguments.certPrefix : 'CERT';
        this.batchSize   = (roundArguments && roundArguments.batchSize) ? parseInt(roundArguments.batchSize, 10) : 1;
        
        console.log(`Worker ${workerIndex}: Initialized for VerifyCertificate (Target: ${this.totalIssued} certs, Prefix: ${this.certPrefix}, BatchSize: ${this.batchSize})`);
    }

    async submitTransaction() {
        this.txIndex++;
        
        const w = this.workerIndex || 0;
        const issuedPerWorker = Math.floor(this.totalIssued / this.totalWorkers);
        const safeIssuedCount = Math.max(issuedPerWorker - 100, 10); 
        
        let certID;

        if (this.certPrefix === 'BCERT') {
            // S4 key scheme: BCERT_{w}_{txIndex}_{certIndex}
            const txIdx   = (Math.floor((this.txIndex - 1) / this.batchSize) % safeIssuedCount) + 1;
            const certIdx = (this.txIndex - 1) % this.batchSize;
            certID = `BCERT_${w}_${txIdx}_${certIdx}`;
        } else {
            // S1/S3 key scheme: CERT_{w}_{idx}
            const idx = ((this.txIndex - 1) % safeIssuedCount) + 1;
            certID = `CERT_${w}_${idx}`;
        }
        
        const request = {
            contractId: this.roundArguments.contractId || 'bcms-sha256',
            contractFunction: 'VerifyCertificateByID',
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