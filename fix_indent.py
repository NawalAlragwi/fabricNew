import os, glob

path = 'caliper-workspace/All_benchmarks/**/*.yaml'
files = glob.glob(path, recursive=True)

count = 0
for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        try:
            with open(filepath, 'r', encoding='windows-1252') as f:
                content = f.read()
        except Exception:
            with open(filepath, 'r', encoding='utf-16') as f:
                content = f.read()
            
    # Fix the indentation
    if '                containers:' in content:
        content = content.replace('                containers:', '        containers:')
        count += 1
    
    with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)
print(f'Fixed encoding and indentation for {count} YAML files.')
