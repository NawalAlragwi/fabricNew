import yaml
import glob
import os

hash_only_round = {
    'label': 'HashOnlyBenchmark',
    'description': 'HashOnlyBenchmark pure CPU test',
    'txDuration': 30,
    'rateControl': {
        'type': 'fixed-rate',
        'opts': {'tps': 10}
    },
    'workload': {
        'module': 'workload/hashOnlyBenchmark.js',
        'arguments': {
            'contractId': 'bcms-hybrid-batch',
            'payloadSize': 20000
        }
    },
    'txOptions': {
        'invokerIdentity': 'User1@org1.example.com'
    }
}

yaml_files = [
    "caliper-workspace/benchmarks/benchConfig_s4_hybrid_batch.yaml",
    "caliper-workspace/benchmarks/benchConfig-S4-HybridBatch.yaml"
]

for file_path in yaml_files:
    if not os.path.exists(file_path):
        continue
    with open(file_path, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
    
    if not data or 'test' not in data or 'rounds' not in data['test']:
        continue
        
    has_hash_only = any(r.get('label') == 'HashOnlyBenchmark' for r in data['test']['rounds'])
    
    if not has_hash_only:
        data['test']['rounds'].insert(0, hash_only_round)
        with open(file_path, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
        print(f"Added HashOnlyBenchmark to {os.path.basename(file_path)}")
    else:
        print(f"HashOnlyBenchmark already exists in {os.path.basename(file_path)}")
