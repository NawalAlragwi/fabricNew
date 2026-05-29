#!/bin/bash
set -e

cd /mnt/c/Users/USERW/pro1/fabricNew/caliper-workspace

# تأكد من وجود مجلد reports
mkdir -p reports

# غيّر networkConfig إلى bcms-blake3
sed -i 's/bcms-sha256/bcms-blake3/g' networks/networkConfig.yaml
echo "✓ networkConfig updated to bcms-blake3"

# BLAKE3 tps50
echo ""
echo "══════════════════════════════════════════"
echo "  BLAKE3 — TPS 50"
echo "══════════════════════════════════════════"
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-benchconfig All_benchmarks/blake3/bcms-s-blake3-tps50.yaml \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-timeout-invokeorquery 120000
cp report.html reports/blake3-tps50.html
echo "✓ blake3-tps50 done"

# BLAKE3 tps100
echo ""
echo "══════════════════════════════════════════"
echo "  BLAKE3 — TPS 100"
echo "══════════════════════════════════════════"
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-benchconfig All_benchmarks/blake3/bcms-s-blake3-tps100.yaml \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-timeout-invokeorquery 120000
cp report.html reports/blake3-tps100.html
echo "✓ blake3-tps100 done"

# BLAKE3 tps150
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
cp report.html reports/blake3-tps150.html
echo "✓ blake3-tps150 done"

# BLAKE3 tps200
echo ""
echo "══════════════════════════════════════════"
echo "  BLAKE3 — TPS 200"
echo "══════════════════════════════════════════"
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-benchconfig All_benchmarks/blake3/bcms-s-blake3-tps200.yaml \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-timeout-invokeorquery 120000
cp report.html reports/blake3-tps200.html
echo "✓ blake3-tps200 done"

echo ""
echo "══════════════════════════════════════════"
echo "  ✅ ALL BLAKE3 BENCHMARKS COMPLETE!"
echo "══════════════════════════════════════════"
echo "Reports saved in: reports/"
ls -la reports/blake3-*.html
