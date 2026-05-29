import os

out_dir = "caliper-workspace/All_benchmarks/hybrid-batch"
os.makedirs(out_dir, exist_ok=True)

tps_values = {
    50: {"issue": 8, "verify_start": 10, "verify_end": 50, "issued": 480},
    100: {"issue": 15, "verify_start": 20, "verify_end": 100, "issued": 900},
    150: {"issue": 22, "verify_start": 30, "verify_end": 150, "issued": 1320},
    200: {"issue": 30, "verify_start": 40, "verify_end": 200, "issued": 1800},
    250: {"issue": 38, "verify_start": 50, "verify_end": 250, "issued": 2280},
}

template = """test:
  name: bcms-s-hybrid-batch-tps{tps}
  description: 'Scenario S4 Hybrid-Batch at {tps} TPS target (UNIFIED CONFIG)'
  workers:
    type: local
    number: 4
  rounds:
    - label: IssueCertificate
      description: 'Issue batch certs at {issue} TPS, 60s'
      txDuration: 60
      rateControl:
        type: fixed-rate
        opts:
          tps: {issue}
      workload:
        module: workload/issueCertificateBatch.js
        arguments:
          contractId: bcms-hybrid-batch
          batchSize: 10
          payloadSize: 5000
      txOptions:
        invokerIdentity: User1@org1.example.com
    - label: HashOnlyBenchmark
      description: 'PURE CPU ROUND - isolate crypto overhead'
      txDuration: 60
      rateControl:
        type: fixed-rate
        opts:
          tps: 10
      workload:
        module: workload/hashOnlyBenchmark.js
        arguments:
          contractId: bcms-hybrid-batch
          payloadSize: 20000
      txOptions:
        invokerIdentity: User1@org1.example.com
    - label: VerifyCertificate
      description: 'PRIMARY ROUND - linear {v_start}->{v_end} TPS, 120s'
      txDuration: 120
      rateControl:
        type: linear-rate
        opts:
          startingTps: {v_start}
          finishingTps: {v_end}
      workload:
        module: workload/verifyCertificate.js
        arguments:
          contractId: bcms-hybrid-batch
          totalIssued: {issued}
          certPrefix: BCERT
          batchSize: 10
      txOptions:
        invokerIdentity: User1@org1.example.com
"""

for tps, data in tps_values.items():
    content = template.format(
        tps=tps, 
        issue=data['issue'], 
        v_start=data['verify_start'], 
        v_end=data['verify_end'], 
        issued=data['issued']
    )
    with open(os.path.join(out_dir, f"bcms-s-hybrid-batch-tps{tps}.yaml"), "w", encoding='utf-8') as f:
        f.write(content)

print("S4 benchmarks generated successfully.")
