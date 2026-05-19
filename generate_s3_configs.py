import os

tps_values = [50, 100, 150, 200]
src_dir = 'caliper-workspace/benchmarks'

for tps in tps_values:
    src_file = f'{src_dir}/benchConfig_s1_sha256_tps{tps}.yaml'
    dst_file = f'{src_dir}/benchConfig_s3_hybrid_tps{tps}.yaml'
    
    with open(src_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    content = content.replace('S1 — SHA-256 Baseline', 'S3 — Hybrid Baseline')
    content = content.replace('bcms-s1-sha256', 'bcms-s3-hybrid')
    content = content.replace('Scenario S1 SHA-256 Baseline', 'Scenario S3 Hybrid Baseline')
    content = content.replace('contractId: bcms-sha256', 'contractId: bcms-hybrid')
    content = content.replace('SHA-256 linear', 'Hybrid linear')
    content = content.replace('Expected: SHA-256 saturates', 'Expected: Hybrid saturates')
    content = content.replace('bcms-sha256', 'bcms-hybrid')
    
    with open(dst_file, 'w', encoding='utf-8') as f:
        f.write(content)
        
print("Successfully generated 4 config files for M3.")
