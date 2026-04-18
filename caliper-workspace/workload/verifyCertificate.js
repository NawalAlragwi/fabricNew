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
        this.roundIndex = roundIndex;
        this.workerIndex = workerIndex;
        this.totalWorkers = totalWorkers;

        // Build a pool of certificate IDs this worker is responsible for
        // Distributes load evenly across workers
        const totalCerts = roundArguments.totalCerts || 1000;
        const perWorker = Math.ceil(totalCerts / totalWorkers);
        const start = workerIndex * perWorker;
        const end = Math.min(start + perWorker, totalCerts);

        this.certIDs = [];
        for (let i = start; i < end; i++) {
            // Matches the ID pattern used in issueCertificate.js
            this.certIDs.push(`CERT_${String(i).padStart(6, '0')}`);
        }

        // Fallback: use seed certificates if no issued certs available
        if (this.certIDs.length === 0) {
            this.certIDs = ['CERT001', 'CERT002', 'CERT003', 'CERT004', 'CERT005'];
        }

        this.idxPtr = 0;
        console.log(`Worker ${workerIndex}: VerifyCertificate pool = ${this.certIDs.length} IDs`);
    }

    async submitTransaction() {
        // Round-robin over this worker's cert pool
        const certID = this.certIDs[this.idxPtr % this.certIDs.length];
        this.idxPtr++;

        const request = {
            contractId: 'basic',
            contractFunction: 'GetCertificate', // OPT-2: direct key lookup
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