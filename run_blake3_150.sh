#!/bin/bash
set -e

cd /mnt/c/Users/USERW/pro1/fabricNew/caliper-workspace

# تأكد من وجود مجلد reports
mkdir -p reports

# غيّر networkConfig إلى bcms-blake3
sed -i 's/bcms-sha256/bcms-blake3/g' networks/networkConfig.yaml
echo "✓ networkConfig updated to bcms-blake3"

echo ""
echo "══════════════════════════════════════════"
echo "  BLAKE3 — TPS 150"
echo "══════════════════════════════════════════"
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-benchconfig All_benchmarks/blake3/bcms-s-blake3-tps150.yaml \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-timeout-invokeorquery 120000

cp report.html reports/blake3-tps150-fixed.html
echo "✓ blake3-tps150 done"
