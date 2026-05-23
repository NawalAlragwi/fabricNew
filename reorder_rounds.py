import yaml
import glob
import os

target_dir = "caliper-workspace/All_benchmarks/hybrid"
yaml_files = glob.glob(os.path.join(target_dir, "*.yaml"))

for file_path in yaml_files:
    with open(file_path, 'r') as f:
        data = yaml.safe_load(f)
    
    rounds = data['test']['rounds']
    
    # Separate the rounds
    issue_round = next((r for r in rounds if r.get('label') == 'IssueCertificate'), None)
    hash_round = next((r for r in rounds if r.get('label') == 'HashOnlyBenchmark'), None)
    verify_round = next((r for r in rounds if r.get('label') == 'VerifyCertificate'), None)
    
    new_rounds = []
    if issue_round: new_rounds.append(issue_round)
    if hash_round: new_rounds.append(hash_round)
    if verify_round: new_rounds.append(verify_round)
    
    data['test']['rounds'] = new_rounds
    
    with open(file_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    print(f"Reordered {os.path.basename(file_path)}")

