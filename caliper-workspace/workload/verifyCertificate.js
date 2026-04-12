'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const { blake3 } = require('@noble/hashes/blake3');
const { buildDeterministicMetadata } = require('./metadataUtil');

const ISSUE_DATE = '2026-04-13';

/**
 * Replicates chaincode ComputeCertHash (BLAKE3): hash(fields) || hash(metadata) → final BLAKE3.
 * @param {string} studentID
 * @param {string} studentName
 * @param {string} degree
 * @param {string} issuer
 * @param {string} issueDate
 * @param {string} metadata
 * @returns {string} hex
 */
function computeCertHashHex(studentID, studentName, degree, issuer, issueDate, metadata) {
    const enc = new TextEncoder();
    const fields = [studentID, studentName, degree, issuer, issueDate].join('|');
    const hash1 = blake3(enc.encode(fields));
    const hash2 = blake3(enc.encode(metadata));
    const combined = new Uint8Array(64);
    combined.set(hash1, 0);
    combined.set(hash2, 32);
    const finalHash = blake3(combined);
    return Buffer.from(finalHash).toString('hex');
}

/**
 * ══════════════════════════════════════════════════════════════════════
 *  VerifyCertificate Workload — BCMS Benchmark
 * ══════════════════════════════════════════════════════════════════════
 *  Client hash must match on-chain CertHash (BLAKE3 with metadata).
 * ══════════════════════════════════════════════════════════════════════
 */
class VerifyCertificateWorkload extends WorkloadModuleBase {
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

        const workerIdx   = this.workerIndex || 0;
        const certID      = `CERT_${workerIdx}_${this.txIndex}`;
        const studentID   = `STU_${workerIdx}_${this.txIndex}`;
        const studentName = `Student_${workerIdx}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        const issuer      = 'Digital University';
        const issueDate   = ISSUE_DATE;
        const metadata    = buildDeterministicMetadata(workerIdx, this.txIndex);
        const certHash    = computeCertHashHex(studentID, studentName, degree, issuer, issueDate, metadata);

        const request = {
            contractId:        'basic',
            contractFunction:  'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly:          true
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports = { createWorkloadModule: () => new VerifyCertificateWorkload() };
