'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class HashOnlyBenchmarkWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        this.payloadSize = 50000;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
        this.payloadSize = (roundArguments && roundArguments.payloadSize) 
            ? parseInt(roundArguments.payloadSize, 10) 
            : 50000;
    }

    async submitTransaction() {
        this.txIndex++;
        
        // Generate a large payload of 'X's
        const payload = 'X'.repeat(this.payloadSize);

        const request = {
            contractId: this.roundArguments.contractId || 'bcms-sha256',
            contractFunction: 'HashOnlyBenchmark',
            invokerIdentity: 'User1@org1.example.com',
            contractArguments: [payload],
            readOnly: true
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() { }
}

function createWorkloadModule() {
    return new HashOnlyBenchmarkWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
