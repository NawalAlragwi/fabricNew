#!/bin/bash
# ============================================================
# fix_sha256.sh — إصلاح smartcontract_sha256.go في مكانه
# يُصلح 3 مشاكل:
#   1. MagnificationFactor: 1000 → 5000
#   2. ComputeCertHash: largeData → loop مباشر
#   3. HashOnlyBenchmark: التأكد من وجود loop
# ============================================================

FILE="/mnt/c/Users/USERW/pro1/fabricNew/chaincode-bcms/sha256/smartcontract_sha256.go"

echo "=== قبل الإصلاح ==="
grep "const MagnificationFactor" "$FILE"
grep "largeData" "$FILE" | head -3

# ── الإصلاح 1: رفع MagnificationFactor ──────────────────────
sed -i 's/const MagnificationFactor = 1000/const MagnificationFactor = 5000/' "$FILE"

# ── الإصلاح 2: استبدال منطق largeData بـ loop مباشر ─────────
# البحث عن الكتلة القديمة واستبدالها
python3 << 'PYEOF'
import re

filepath = "/mnt/c/Users/USERW/pro1/fabricNew/chaincode-bcms/sha256/smartcontract_sha256.go"

with open(filepath, 'r') as f:
    content = f.read()

# الكود القديم — largeData strategy
old_pattern = r'(\t// Step 2: Data Magnification.*?\n)(\t// Create a large buffer.*?\n)(\t// This forces.*?\n)(\tlargeData := make\(\[\]byte, len\(data\)\*MagnificationFactor\)\n)(\tfor i := 0; i < MagnificationFactor; i\+\+ \{\n)(\t\tcopy\(largeData\[i\*len\(data\):\], data\)\n)(\t\}\n)(\n)?(\t// Step 3: Compute single hash of the large block\.\n)(\t// SHA-256: sequential processing of the entire block\.\n)(\thash := sha256\.Sum256\(largeData\)\n)'

# الكود الجديد — loop مباشر
new_code = '''\t// Step 2: Loop Magnification — FIX-PARITY v14
\t// Identical structure to BLAKE3 v14: repeated calls on same data.
\t// Measures per-call overhead accurately for fair comparison.
\t// SHA-256: ~15µs × 5000 = 75ms per tx — visible in Caliper above 20 TPS.
\tvar h [32]byte
\tfor i := 0; i < MagnificationFactor; i++ {
\t\th = sha256.Sum256(data)
\t}
\thash := fmt.Sprintf("%x", h)
\t_ = hash
'''

match = re.search(old_pattern, content, re.DOTALL)
if match:
    new_content = content[:match.start()] + new_code + content[match.end():]
    
    # إصلاح سطر return — استبدل fmt.Sprintf("%x", hash) بـ hash مباشرة
    # لأن hash الآن هو string مباشرة
    new_content = new_content.replace(
        '\treturn fmt.Sprintf("%x", hash), HashModeSHA256',
        '\treturn hash, HashModeSHA256'
    )
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    print("✓ تم إصلاح ComputeCertHash بنجاح")
else:
    print("⚠ النمط القديم لم يُوجد — محاولة إصلاح يدوي...")
    # إصلاح بديل أبسط — استبدل السطرين الرئيسيين فقط
    content2 = content.replace(
        '\tlargeData := make([]byte, len(data)*MagnificationFactor)\n\tfor i := 0; i < MagnificationFactor; i++ {\n\t\tcopy(largeData[i*len(data):], data)\n\t}\n\n\t// Step 3: Compute single hash of the large block.\n\t// SHA-256: sequential processing of the entire block.\n\thash := sha256.Sum256(largeData)',
        '\t// FIX-PARITY v14: loop on same data — identical to BLAKE3\n\tvar h [32]byte\n\tfor i := 0; i < MagnificationFactor; i++ {\n\t\th = sha256.Sum256(data)\n\t}\n\thash := h'
    )
    if content2 != content:
        # إصلاح return
        content2 = content2.replace(
            '\treturn fmt.Sprintf("%x", hash), HashModeSHA256',
            '\treturn fmt.Sprintf("%x", hash), HashModeSHA256'
        )
        with open(filepath, 'w') as f:
            f.write(content2)
        print("✓ تم الإصلاح البديل")
    else:
        print("✗ لم يتم الإصلاح — يحتاج تدخل يدوي")
PYEOF

echo ""
echo "=== بعد الإصلاح ==="
grep "const MagnificationFactor" "$FILE"
echo "--- ComputeCertHash ---"
grep -A 12 "func ComputeCertHash" "$FILE" | head -15
echo "--- HashOnlyBenchmark ---"
grep -A 6 "func.*HashOnlyBenchmark" "$FILE" | head -8
echo ""
echo "=== التحقق من بناء الكود ==="
cd "$(dirname $FILE)"
go build ./... && echo "✓ البناء نجح" || echo "✗ خطأ في البناء"
