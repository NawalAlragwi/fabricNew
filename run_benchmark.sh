#!/usr/bin/env bash
# =============================================================================
#  run_benchmark.sh — Caliper Benchmark Warm-up Wrapper
#  Runs a 15s warm-up round, sleeps 10s, then runs the real benchmark N times.
#  Saves each run's report with timestamp.
#  Prints a summary table at the end.
#  Usage: ./run_benchmark.sh <caliper-config.yaml> [N]
# =============================================================================
set -euo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Print help if not enough arguments
if [ "$#" -lt 1 ]; then
    echo -e "${RED}Error: Missing configuration path.${NC}"
    echo "Usage: $0 <caliper-config.yaml> [N]"
    exit 1
fi

CONFIG_FILE="$1"
N="${2:-5}" # Default to 5 runs

# Verify config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file '$CONFIG_FILE' not found.${NC}"
    exit 1
fi

# Determine directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALIPER_WORKSPACE="${SCRIPT_DIR}/caliper-workspace"
REPORTS_DIR="${SCRIPT_DIR}/reports"

# Resolve absolute path of config file
CONFIG_ABS_PATH="$(readlink -f "$CONFIG_FILE")"

# Ensure reports directory exists
mkdir -p "$REPORTS_DIR"

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}  Caliper Benchmark Warm-up Wrapper${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "  Config:      ${YELLOW}$(basename "$CONFIG_FILE")${NC}"
echo -e "  Runs (N):    ${YELLOW}$N${NC}"
echo -e "  Workspace:   ${YELLOW}$CALIPER_WORKSPACE${NC}"
echo -e "  Reports Dir: ${YELLOW}$REPORTS_DIR${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo ""

# 1. Dynamically generate warm-up configuration in caliper-workspace
WARMUP_CONFIG_PATH="${CALIPER_WORKSPACE}/benchmarks/temp_warmup_config.yaml"

echo "Generating temporary warm-up configuration..."
python3 - "$CONFIG_ABS_PATH" "$WARMUP_CONFIG_PATH" << 'PYEOF'
import sys
import yaml

config_path = sys.argv[1]
warmup_path = sys.argv[2]

try:
    with open(config_path, 'r') as f:
        data = yaml.safe_load(f)

    if 'test' in data and 'rounds' in data['test'] and len(data['test']['rounds']) > 0:
        first_round = data['test']['rounds'][0]
        warmup_round = {
            'label': 'Warmup_' + first_round.get('label', 'round'),
            'description': 'Warm-up round (15s @ 10 TPS) to stabilize the environment',
            'txDuration': 15,
            'rateControl': {
                'type': 'fixed-rate',
                'opts': {
                    'tps': 10
                }
            },
            'workload': first_round.get('workload'),
            'txOptions': first_round.get('txOptions')
        }
        # Keep other configuration settings but set rounds to just this one
        data['test']['rounds'] = [warmup_round]
    else:
        print("Error: Could not find test rounds in config", file=sys.stderr)
        sys.exit(1)

    with open(warmup_path, 'w') as f:
        yaml.safe_dump(data, f, default_flow_style=False)
    print("Success: Generated warm-up config at", warmup_path)
except Exception as e:
    print(f"Error generating warm-up config: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Cleanup warm-up config on exit
cleanup() {
    rm -f "$WARMUP_CONFIG_PATH"
}
trap cleanup EXIT

# 2. Main Run Loop
REPORTS_LIST=()
for (( run=1; run<=N; run++ )); do
    echo -e "${BOLD}${BLUE}-------------------------------------------------------------${NC}"
    echo -e "${BOLD}${BLUE}  Run $run / $N${NC}"
    echo -e "${BOLD}${BLUE}-------------------------------------------------------------${NC}"

    # A. Run Warm-up Round
    echo -e "[$(date '+%H:%M:%S')] Starting warm-up round (15s @ 10 TPS)..."
    
    # Run Caliper
    (
        cd "$CALIPER_WORKSPACE"
        NO_PROXY="localhost,127.0.0.1" no_proxy="localhost,127.0.0.1" \
        http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" \
        CALIPER_FABRIC_TIMEOUT_INVOKEORQUERY=120000 \
        npx caliper launch manager \
            --caliper-workspace . \
            --caliper-networkconfig networks/networkConfig.yaml \
            --caliper-benchconfig "$WARMUP_CONFIG_PATH" \
            --caliper-flow-only-test > /dev/null 2>&1
    )
    
    echo -e "[$(date '+%H:%M:%S')] ${GREEN}Warm-up completed.${NC}"

    # B. Sleep between warm-up and real run
    echo -e "[$(date '+%H:%M:%S')] ${YELLOW}Sleeping 10 seconds to cool down...${NC}"
    sleep 10

    # C. Run Real Benchmark
    echo -e "[$(date '+%H:%M:%S')] Starting real benchmark..."
    
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    REAL_REPORT_FILE="${REPORTS_DIR}/$(basename "${CONFIG_FILE%.*}")_run${run}_${TIMESTAMP}_report.html"
    
    # We want to capture real benchmark logs and report
    (
        cd "$CALIPER_WORKSPACE"
        rm -f report.html 2>/dev/null || true
        
        NO_PROXY="localhost,127.0.0.1" no_proxy="localhost,127.0.0.1" \
        http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" \
        CALIPER_FABRIC_TIMEOUT_INVOKEORQUERY=120000 \
        npx caliper launch manager \
            --caliper-workspace . \
            --caliper-networkconfig networks/networkConfig.yaml \
            --caliper-benchconfig "$CONFIG_ABS_PATH" \
            --caliper-flow-only-test
    )
    
    # Save the report
    if [ -f "${CALIPER_WORKSPACE}/report.html" ]; then
        cp "${CALIPER_WORKSPACE}/report.html" "$REAL_REPORT_FILE"
        echo -e "[$(date '+%H:%M:%S')] ${GREEN}Real run completed. Report saved to $REAL_REPORT_FILE${NC}"
        REPORTS_LIST+=("$REAL_REPORT_FILE")
    else
        echo -e "${RED}Error: Real run did not generate report.html${NC}"
        exit 1
    fi
    echo ""
done

# 3. Print Summary Table at the end
echo -e "${BOLD}${BLUE}========================================================================================${NC}"
echo -e "${BOLD}${BLUE}  BENCHMARK RUNS SUMMARY TABLE${NC}"
echo -e "${BOLD}${BLUE}========================================================================================${NC}"
python3 - "${REPORTS_LIST[@]}" << 'PYEOF'
import sys
import re

reports = sys.argv[1:]

print(f"{'Run':<6} | {'Round Name':<20} | {'Success':<8} | {'Fail':<6} | {'Send Rate':<10} | {'Throughput':<12} | {'Avg Lat':<8} | {'Max Lat':<8}")
print("-" * 92)

for idx, report_path in enumerate(reports):
    run_num = idx + 1
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        summary_match = re.search(r'id="benchmarksummary".*?</table>', content, re.DOTALL)
        summary_html = summary_match.group(0) if summary_match else content
        rows = re.findall(r'<tr[^>]*>(.*?)</tr>', summary_html, re.DOTALL)
        
        first_row = True
        for row in rows:
            cells = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL)
            if len(cells) >= 8:
                clean = [re.sub(r'<[^>]*>', '', c).strip() for c in cells]
                name = clean[0]
                succ = clean[1]
                fail = clean[2]
                send_rate = clean[3] + " TPS"
                throughput = clean[7] + " TPS"
                avg_lat = clean[6] + "s"
                max_lat = clean[4] + "s"
                
                run_str = f"Run {run_num}" if first_row else ""
                print(f"{run_str:<6} | {name:<20} | {succ:<8} | {fail:<6} | {send_rate:<10} | {throughput:<12} | {avg_lat:<8} | {max_lat:<8}")
                first_row = False
        print("-" * 92)
    except Exception as e:
        print(f"Run {run_num}: Failed to parse report ({e})")
PYEOF
echo -e "${BOLD}${BLUE}========================================================================================${NC}"
