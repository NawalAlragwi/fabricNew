import re
import glob

files = [
    '/mnt/c/Users/USERW/pro1/fabricNew/caliper-workspace/reports/table9/table9_M1_SHA256.html',
    '/mnt/c/Users/USERW/pro1/fabricNew/caliper-workspace/reports/table9/table9_M2_BLAKE3.html',
    '/mnt/c/Users/USERW/pro1/fabricNew/caliper-workspace/reports/table9/table9_M3_Hybrid.html',
    '/mnt/c/Users/USERW/pro1/fabricNew/caliper-workspace/reports/table9/table9_M4_HybridBatch.html'
]

for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        print(f'\n=== {filepath.split("/")[-1]} ===')
        
        matches = re.findall(r'<tr>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*</tr>', content)
        
        for m in matches:
            name = re.sub('<[^<]+>', '', m[0]).strip()
            succ = re.sub('<[^<]+>', '', m[1]).strip()
            fail = re.sub('<[^<]+>', '', m[2]).strip()
            max_lat = re.sub('<[^<]+>', '', m[4]).strip()
            avg_lat = re.sub('<[^<]+>', '', m[6]).strip()
            tps = re.sub('<[^<]+>', '', m[7]).strip()
            
            if name != 'Name':
                print(f'{name} | Succ: {succ} | Fail: {fail} | MaxLat: {max_lat}s | AvgLat: {avg_lat}s | TPS: {tps}')
    except Exception as e:
        print(f'Error reading {filepath}: {e}')
