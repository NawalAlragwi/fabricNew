'use strict';

/**
 * Deterministic ~200KB metadata shared by IssueCertificate and VerifyCertificate workloads.
 * Must stay in sync with chaincode expectations: same string → same BLAKE3 hash on-chain.
 */

const METADATA_MIN_BYTES = 200 * 1024;

/**
 * @param {number} workerIdx
 * @param {number} txIdx
 * @returns {string}
 */
function buildDeterministicMetadata(workerIdx, txIdx) {
    const header = JSON.stringify({
        source:    'bcms-blake3-benchmark',
        algorithm: 'BLAKE3',
        worker:    workerIdx,
        txIndex:   txIdx,
        payloadVersion: 'deterministic-v1',
        description: 'Fixed padding for reproducible BLAKE3 hash in VerifyCertificate round.',
    });
    const padLen = Math.max(1024, METADATA_MIN_BYTES - header.length - 16);
    const padding = 'P'.repeat(padLen);
    return `${header}|||${padding}`;
}

module.exports = { buildDeterministicMetadata, METADATA_MIN_BYTES };
