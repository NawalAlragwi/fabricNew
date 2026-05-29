#!/bin/bash
# =============================================================================
# run_remaining_runs.sh — يكمل الـ runs الناقصة لكل نموذج
#
# الوضع الحالي:
#   M1 (SHA256):  5 runs موجودة (run1-5) → يحتاج 5 runs إضافية (run6-10)
#   M2 (BLAKE3):  5 runs موجودة (run1-5) → يحتاج 5 runs إضافية (run6-10)
#   M3 (Hybrid):  5 runs موجودة (run1-5) → يحتاج 5 runs إضافية (run6-10)
# =============================================================================

export NODE_OPTIONS="--max-old-space-size=8192"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_BASE="${SCRIPT_DIR}/../results"

TOTAL_START=$(date +%s)
FAILED_ANY=0

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║     Completing Remaining Benchmark Runs (run6-10)        ║${NC}"
echo -e "${BOLD}${CYAN}║  M1: +5  |  M2: +5  |  M3: +5                           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# دالة تشغيل نموذج معين
# run_model <label> <bench_config> <results_subdir> <start_run> <end_run>
# ──────────────────────────────────────────────────────────────────────────────
run_model() {
    local label="$1"
    local bench_config="$2"
    local results_subdir="$3"
    local start_run="$4"
    local end_run="$5"

    local model_start total_runs
    model_start=$(date +%s)
    total_runs=$(( end_run - start_run + 1 ))

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  ${label}: تشغيل ${total_runs} runs (من run${start_run} إلى run${end_run})${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    for i in $(seq "$start_run" "$end_run"); do
        local elapsed_sec=$(( $(date +%s) - model_start ))
        local done_count=$(( i - start_run ))
        local pct=$(( done_count * 100 / total_runs ))
        local bar_len=20
        local filled=$(( pct * bar_len / 100 ))
        local bar=""
        for ((b=0; b<filled; b++)); do bar+="█"; done
        for ((b=filled; b<bar_len; b++)); do bar+="░"; done
        local elapsed_fmt
        elapsed_fmt=$(printf '%dh%02dm%02ds' $((elapsed_sec/3600)) $((elapsed_sec%3600/60)) $((elapsed_sec%60)))

        echo ""
        echo -e "${CYAN}${BOLD}  ┌─ [${label} | Run ${i}/${end_run}] ${bar} ${pct}% | ${elapsed_fmt}${NC}"
        echo -e "${BLUE}[$(date '+%H:%M:%S')] [INFO]${NC}  === [${label} | Run ${i}] Started at $(date '+%Y-%m-%d %H:%M:%S') ==="

        # شغّل caliper
        npx caliper launch manager \
            --caliper-workspace . \
            --caliper-networkconfig networks/networkConfig.yaml \
            --caliper-benchconfig "$bench_config" \
            --caliper-flow-only-test \
            --caliper-fabric-gateway-enabled

        local OUT_DIR="${RESULTS_BASE}/${results_subdir}/run${i}"
        mkdir -p "$OUT_DIR"

        if [ -f report.html ]; then
            mv report.html "$OUT_DIR/caliper_raw_report.html"
            echo -e "${GREEN}[$(date '+%H:%M:%S')] [OK]${NC}    ✅ Run ${i} → $OUT_DIR/caliper_raw_report.html"
        else
            echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} ❌ report.html غير موجود للـ Run ${i}"
            FAILED_ANY=1
        fi

        # انتظر لاستقرار الشبكة
        if [ "$i" -lt "$end_run" ]; then
            echo -e "${YELLOW}⏳ Waiting 60s for network to stabilize...${NC}"
            sleep 60
        fi
    done

    local total_sec=$(( $(date +%s) - model_start ))
    echo ""
    echo -e "${GREEN}[$(date '+%H:%M:%S')] [OK]${NC}    ${label} انتهى في $(printf '%dh%02dm%02ds' $((total_sec/3600)) $((total_sec%3600/60)) $((total_sec%60)))"
}

# ──────────────────────────────────────────────────────────────────────────────
# تشغيل النماذج
# ──────────────────────────────────────────────────────────────────────────────

# M1: SHA256 — من run6 إلى run10
run_model "M1-SHA256" \
    "All_benchmarks/sha256/bcms-s-sha256-tps200.yaml" \
    "10run_M1/tps200" \
    6 10

# M2: BLAKE3 — من run6 إلى run10
run_model "M2-BLAKE3" \
    "All_benchmarks/blake3/bcms-s-blake3-tps200.yaml" \
    "20run_M2/tps200" \
    6 10

# M3: Hybrid — من run6 إلى run10
run_model "M3-Hybrid" \
    "All_benchmarks/hybrid/bcms-s-hybrid-tps200.yaml" \
    "30run_M3/tps200" \
    6 10

# ──────────────────────────────────────────────────────────────────────────────
# ملخص نهائي
# ──────────────────────────────────────────────────────────────────────────────
TOTAL_SEC=$(( $(date +%s) - TOTAL_START ))

echo ""
if [ "$FAILED_ANY" -eq 0 ]; then
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║         🎉 ALL REMAINING RUNS COMPLETED SUCCESSFULLY!    ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║   ⚠️  DONE — بعض الـ runs فشلت، راجع الأخطاء أعلاه     ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
fi

echo -e "  Total time: $(printf '%dh%02dm%02ds' $((TOTAL_SEC/3600)) $((TOTAL_SEC%3600/60)) $((TOTAL_SEC%60)))"
echo ""
echo -e "${BOLD}النتائج محفوظة في:${NC}"
echo -e "  M1 → ${RESULTS_BASE}/10run_M1/tps200/run{6..10}/"
echo -e "  M2 → ${RESULTS_BASE}/20run_M2/tps200/run{6..10}/"
echo -e "  M3 → ${RESULTS_BASE}/30run_M3/tps200/run{6..10}/"
