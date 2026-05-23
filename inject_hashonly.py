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
            'contractId': 'bcms-hybrid',
            'payloadSize': 20000
        }
    },
    'txOptions': {
        'invokerIdentity': 'User1@org1.example.com'
    }
}

target_dir = "caliper-workspace/All_benchmarks/hybrid"
yaml_files = glob.glob(os.path.join(target_dir, "*.yaml"))

for file_path in yaml_files:
    with open(file_path, 'r') as f:
        data = yaml.safe_load(f)
    
    # Check if HashOnlyBenchmark is already in the rounds
    has_hash_only = any(r.get('label') == 'HashOnlyBenchmark' for r in data['test']['rounds'])
    
    if not has_hash_only:
        # Insert HashOnlyBenchmark at the beginning of the rounds
        data['test']['rounds'].insert(0, hash_only_round)
        
        with open(file_path, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)
        print(f"Added HashOnlyBenchmark to {os.path.basename(file_path)}")
    else:
        print(f"HashOnlyBenchmark already exists in {os.path.basename(file_path)}")

