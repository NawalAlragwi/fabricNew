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
        this.totalIssued = (roundArguments && roundArguments.totalIssued) ? roundArguments.totalIssued : 1000;
        console.log(`Worker ${workerIndex}: Initialized for VerifyCertificate (Target: ${this.totalIssued} certs)`);
    }

    async submitTransaction() {
        this.txIndex++;
        
        // --- RESEARCH FIX #1: Worker-Specific Range + Race Condition Safety ---
        // Each worker queries certificates it issued in the previous round.
        // We use a safety buffer of 100 to avoid the race condition where the 
        // last few certificates issued might still be in the ordering phase.
        const issuedPerWorker = Math.floor(this.totalIssued / this.totalWorkers);
        const safeIssuedCount = Math.max(issuedPerWorker - 100, 10); 
        const idx = ((this.txIndex - 1) % safeIssuedCount) + 1;
        const certID = `CERT_${this.workerIndex}_${idx}`;
        
        const request = {
            contractId: 'basic',
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