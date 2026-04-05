'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * ══════════════════════════════════════════════════════════════════════════
 *  IssueCertificate Workload — BCMS BLAKE3 Benchmark  (fabric-blake3-new)
 * ══════════════════════════════════════════════════════════════════════════
 *
 *  Target chaincode: chaincode-bcms/blake3 (deployed as bcms-blake3)
 *
 *  Function signature (smartcontract_blake3.go):
 *    IssueCertificate(
 *      id, studentID, studentName, degree, issuer, issueDate,
 *      certHashInput, signature
 *    ) error
 *
 *  MVCC Safety:
 *    - Each worker generates a UNIQUE ID: CERT_{workerIndex}_{txIndex}
 *    - No two workers share a key → zero phantom-read conflicts
 *    - Idempotent: duplicate ID returns nil (not error)
 *
 *  Native BLAKE3 Crypto (client-side):
 *    certHash is computed as SHA-256 on the client. The chaincode itself
 *    applies BLAKE3 natively via lukechampine.com/blake3 on the Go side.
 *    The client sends certHashInput as a SHA-256 pre-hash; chaincode
 *    accepts it or recomputes BLAKE3(fields) if empty.
 *    DO NOT use blake3-js — Native BLAKE3 runs inside the Go chaincode.
 *
 *  CouchDB Index Alignment:
 *    Documents are stored with docType="certificate", StudentID, Issuer
 *    matching the index defined in META-INF/statedb/couchdb/indexes/
 *    indexCertificates.json — ensuring all rich queries hit the index.
 * ══════════════════════════════════════════════════════════════════════════
 */
class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex   = 0;
        this.issueDate = '';
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex   = 0;
        // Freeze issueDate per worker-round so all certs in a batch share the same date
        this.issueDate = new Date().toISOString().split('T')[0];
    }

    async submitTransaction() {
        this.txIndex++;

        const w           = this.workerIndex || 0;
        const certID      = `CERT_${w}_${this.txIndex}`;
        // StudentID and Issuer must match the CouchDB index field names
        const studentID   = `STU_${w}_${this.txIndex}`;
        const studentName = `Student_${w}_${this.txIndex}`;
        const degree      = 'Bachelor of Computer Science';
        // Issuer matches the index field — avoids full-table scan on GetCertificatesByStudent
        const issuer      = 'Digital University';
        const issueDate   = this.issueDate;

        // ── Client-side SHA-256 pre-hash ────────────────────────────────
        // Chaincode applies native BLAKE3 (lukechampine.com/blake3 in Go).
        // We pass the field-based hash as certHashInput; chaincode overwrites
        // with BLAKE3(studentID|studentName|degree|issuer|issueDate) on-chain.
        const fields    = [studentID, studentName, degree, issuer, issueDate].join('|');
        const certHash  = crypto.createHash('sha256').update(fields).digest('hex');

        // ── Digital signature placeholder ────────────────────────────────
        const signature = `SIG_${certID}_${certHash.substring(0, 16)}`;

        const request = {
            contractId:        'bcms-blake3',
            contractFunction:  'IssueCertificate',
            // Args MUST match Go func signature order exactly:
            // (id, studentID, studentName, degree, issuer, issueDate,
            //  certHashInput, signature)
            contractArguments: [
                certID,
                studentID,
                studentName,
                degree,
                issuer,
                issueDate,
                certHash,
                signature,
            ],
            readOnly: false,
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {
        // Idempotent design — no cleanup needed
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
