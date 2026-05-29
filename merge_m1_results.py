#!/usr/bin/env python3
"""
merge_m1_results.py
يستخرج مقاييس M1 من ملفات HTML الموجودة ويدمجها مع CSV النهائي
الاستخدام: python3 merge_m1_results.py
"""
import re, json, glob, os, sys

# ── المسارات ─────────────────────────────────────────────────
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
M1_DIR       = os.path.join(SCRIPT_DIR, "results", "40runs", "M1")
FINAL_CSV    = os.path.join(SCRIPT_DIR, "results", "40runs", "all_runs_raw.csv")
MERGED_CSV   = os.path.join(SCRIPT_DIR, "results", "40runs", "all_runs_merged.csv")
# ─────────────────────────────────────────────────────────────

def extract_from_html(html_path, model, run_num):
    """استخرج المقاييس من HTML report الخاص بـ Caliper"""
    try:
        with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        # ابحث عن صفوف الجدول في HTML
        rows = re.findall(r'<tr[^>]*>(.*?)</tr>', content, re.DOTALL)
        tps = avg_lat = max_lat = min_lat = succ = 0.0

        for row in rows:
            cells = re.findall(r'<td[^>]*>([\d.]+)</td>', row)
            if len(cells) >= 5:
                try:
                    tps     = float(cells[0])
                    avg_lat = float(cells[1])
                    min_lat = float(cells[2])
                    max_lat = float(cells[3])
                    succ    = float(cells[4])
                    if tps > 0:
                        break
                except ValueError:
                    continue

        # Fallback: ابحث عن TPS في النص
        if tps == 0:
            m = re.search(r'(\d+\.?\d*)\s*(?:TPS|tps)', content)
            if m:
                tps = float(m.group(1))

        return f"{model},{run_num},{tps:.4f},{avg_lat:.6f},{max_lat:.6f},{min_lat:.6f},{succ:.2f}"

    except Exception as e:
        print(f"  ⚠ خطأ في {html_path}: {e}")
        return f"{model},{run_num},NA,NA,NA,NA,NA"

def main():
    print("=" * 60)
    print("  دمج نتائج M1 مع CSV النهائي")
    print("=" * 60)

    # ── ابحث عن ملفات HTML لـ M1 ────────────────────────────
    html_files = sorted(glob.glob(os.path.join(M1_DIR, "M1_run*_report.html")))

    if not html_files:
        print(f"\n❌ لم يتم العثور على ملفات HTML في: {M1_DIR}")
        print("   تأكد من المسار الصحيح وأن M1 runs قد نُفِّذت.")
        sys.exit(1)

    print(f"\n✓ وُجد {len(html_files)} ملف HTML لـ M1:")
    for f in html_files:
        print(f"  - {os.path.basename(f)}")

    # ── استخرج المقاييس ──────────────────────────────────────
    m1_rows = []
    for i, html_file in enumerate(html_files, start=1):
        row = extract_from_html(html_file, "M1", i)
        m1_rows.append(row)
        print(f"  Run {i}: {row}")

    # ── اقرأ CSV الحالي (M2+M3+M4) ──────────────────────────
    existing_rows = []
    header = "Model,Run,AvgTPS,AvgLatency,MaxLatency,MinLatency,SuccessRate"

    if os.path.exists(FINAL_CSV):
        with open(FINAL_CSV, 'r') as f:
            lines = f.read().splitlines()
        if lines and lines[0].startswith("Model"):
            header = lines[0]
            existing_rows = lines[1:]
        else:
            existing_rows = lines
        print(f"\n✓ CSV الحالي يحتوي على {len(existing_rows)} سطر (M2+M3+M4)")
    else:
        print(f"\n⚠ لم يُوجد {FINAL_CSV} — سيُنشأ CSV جديد بـ M1 فقط")

    # ── ادمج: M1 أولاً ثم M2+M3+M4 ─────────────────────────
    all_rows = m1_rows + existing_rows

    with open(MERGED_CSV, 'w') as f:
        f.write(header + "\n")
        for row in all_rows:
            if row.strip():
                f.write(row + "\n")

    print(f"\n✅ تم الدمج بنجاح!")
    print(f"   الملف النهائي: {MERGED_CSV}")
    print(f"   إجمالي الأسطر: {len(all_rows)}")
    print(f"\n{'─'*60}")
    print("CSV Preview:")
    print(f"{'─'*60}")
    print(f"{header}")
    for row in all_rows[:10]:
        print(row)
    if len(all_rows) > 10:
        print(f"... و {len(all_rows)-10} سطر إضافية")

if __name__ == "__main__":
    main()
