"""
add_monitors.py
---------------
يضيف قسم monitors لمراقبة موارد Docker في جميع ملفات benchmark YAML
لمشروع Hyperledger Caliper BCMS.
"""

import os
import glob

MONITORS_BLOCK = """
monitors:
  resource:
    - module: docker
      options:
        interval: 5
        containers:
          - peer0.org1.example.com
          - peer0.org2.example.com
          - orderer.example.com
          - couchdb0
          - couchdb1
"""

BASE_DIR = os.path.join(os.path.dirname(__file__), "caliper-workspace", "All_benchmarks")

yaml_files = glob.glob(os.path.join(BASE_DIR, "**", "*.yaml"), recursive=True)
# أضف أيضاً ملفات benchmarks العادية
BENCH_DIR = os.path.join(os.path.dirname(__file__), "caliper-workspace", "benchmarks")
yaml_files += glob.glob(os.path.join(BENCH_DIR, "*.yaml"))

updated = []
skipped = []

for filepath in yaml_files:
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    if "monitors:" in content:
        skipped.append(filepath)
        continue

    # أضف القسم في نهاية الملف (بعد إزالة المسافات الزائدة في النهاية)
    new_content = content.rstrip() + "\n" + MONITORS_BLOCK

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)

    updated.append(filepath)

print(f"\n✅ تم تحديث {len(updated)} ملف:")
for f in updated:
    print(f"   + {os.path.relpath(f)}")

print(f"\n⏭️  تم تخطي {len(skipped)} ملف (monitors موجود مسبقاً):")
for f in skipped:
    print(f"   - {os.path.relpath(f)}")
