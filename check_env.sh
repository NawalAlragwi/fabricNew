#!/usr/bin/env bash
# =============================================================================
#  check_env.sh — Pre-run System Health Check for Caliper Benchmarks
#  Checks CPU load, available RAM, Disk I/O wait, and Docker container status.
#  Prints GO / WARN / FAIL for each check.
#  Exits with code 1 if any critical check fails.
# =============================================================================
set -uo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo -e "${BOLD}${BLUE}  Pre-run System Health Check${NC}"
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
echo ""

CRITICAL_FAILED=0

# 1. CPU Load Average Check
echo -n "Checking CPU Load Average... "
if [ -f /proc/loadavg ]; then
    LOAD_AVG=$(cat /proc/loadavg | cut -d' ' -f1)
else
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
fi

if [ -z "$LOAD_AVG" ]; then
    echo -e "[ ${YELLOW}WARN${NC} ] (Could not read load average)"
else
    # Check if load average > 0.5
    IS_HIGH=$(awk "BEGIN {print ($LOAD_AVG > 0.5) ? 1 : 0}")
    if [ "$IS_HIGH" -eq 1 ]; then
        echo -e "[ ${YELLOW}WARN${NC} ] (Load average is high: ${LOAD_AVG} > 0.5)"
    else
        echo -e "[  ${GREEN}GO${NC}  ] (Load average is optimal: ${LOAD_AVG})"
    fi
fi

# 2. Available RAM Check
echo -n "Checking Available RAM... "
MEM_AVAILABLE_KB=""
if [ -f /proc/meminfo ]; then
    MEM_AVAILABLE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}' || echo "")
    if [ -z "$MEM_AVAILABLE_KB" ]; then
        MEM_FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}' || echo "0")
        BUFFERS_KB=$(grep Buffers /proc/meminfo | awk '{print $2}' || echo "0")
        CACHED_KB=$(grep ^Cached /proc/meminfo | awk '{print $2}' || echo "0")
        MEM_AVAILABLE_KB=$((MEM_FREE_KB + BUFFERS_KB + CACHED_KB))
    fi
fi

if [ -z "$MEM_AVAILABLE_KB" ] || [ "$MEM_AVAILABLE_KB" -eq 0 ]; then
    # Fallback to free command
    MEM_AVAILABLE_MB=$(free -m | awk '/Mem:/ {print $7}')
    MEM_AVAILABLE_GB=$(awk "BEGIN {print $MEM_AVAILABLE_MB / 1024}")
else
    MEM_AVAILABLE_GB=$(awk "BEGIN {print $MEM_AVAILABLE_KB / 1024 / 1024}")
fi

# Check if available RAM < 2GB
IS_LOW_RAM=$(awk "BEGIN {print ($MEM_AVAILABLE_GB < 2.0) ? 1 : 0}")
if [ "$IS_LOW_RAM" -eq 1 ]; then
    echo -e "[ ${YELLOW}WARN${NC} ] (Free RAM is low: $(printf "%.2f" "$MEM_AVAILABLE_GB") GB < 2.0 GB)"
else
    echo -e "[  ${GREEN}GO${NC}  ] (Available RAM: $(printf "%.2f" "$MEM_AVAILABLE_GB") GB)"
fi

# 3. Disk I/O Wait Check
echo -n "Checking Disk I/O Wait... "
IOWAIT_PCT=$(python3 - << 'PYEOF'
import time
import sys

def get_cpu_times():
    try:
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        parts = line.strip().split()
        times = [float(x) for x in parts[1:]]
        # user, nice, system, idle, iowait
        total = sum(times)
        iowait = times[4] if len(times) > 4 else 0.0
        return total, iowait
    except Exception:
        return None

res1 = get_cpu_times()
if res1 is None:
    sys.exit(1)

time.sleep(0.5)
res2 = get_cpu_times()
if res2 is None:
    sys.exit(1)

t1, io1 = res1
t2, io2 = res2

total_diff = t2 - t1
if total_diff > 0:
    iowait_pct = ((io2 - io1) / total_diff) * 100
else:
    iowait_pct = 0.0
print(f"{iowait_pct:.2f}")
PYEOF
)

if [ $? -ne 0 ] || [ -z "$IOWAIT_PCT" ]; then
    echo -e "[ ${YELLOW}WARN${NC} ] (Could not measure I/O wait)"
else
    IS_HIGH_IO=$(awk "BEGIN {print ($IOWAIT_PCT > 5.0) ? 1 : 0}")
    if [ "$IS_HIGH_IO" -eq 1 ]; then
        echo -e "[ ${YELLOW}WARN${NC} ] (Disk I/O wait is high: ${IOWAIT_PCT}% > 5%)"
    else
        echo -e "[  ${GREEN}GO${NC}  ] (Disk I/O wait: ${IOWAIT_PCT}%)"
    fi
fi

# 4. Docker Container Status Check (Critical)
echo -n "Checking Fabric Docker containers... "
REQUIRED_CONTAINERS=(
    "peer0.org1.example.com"
    "peer0.org2.example.com"
    "orderer.example.com"
)

MISSING_CONTAINERS=()
for c in "${REQUIRED_CONTAINERS[@]}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
    STATUS=$(echo "$STATUS" | tr -d '\r\n')
    if [ "$STATUS" != "running" ]; then
        MISSING_CONTAINERS+=("$c ($STATUS)")
    fi
done

if [ ${#MISSING_CONTAINERS[@]} -ne 0 ]; then
    echo -e "[ ${RED}FAIL${NC} ]"
    echo -e "  ${RED}CRITICAL ERROR: The following required Fabric containers are not running:${NC}"
    for mc in "${MISSING_CONTAINERS[@]}"; do
        echo "  - $mc"
    done
    CRITICAL_FAILED=1
else
    echo -e "[  ${GREEN}GO${NC}  ] (All required Fabric containers are running)"
fi

echo ""
echo -e "${BOLD}${BLUE}=====================================================================${NC}"
if [ "$CRITICAL_FAILED" -eq 1 ]; then
    echo -e "${RED}  System Health Check FAILED. Please start the Fabric network.${NC}"
    echo -e "${BOLD}${BLUE}=====================================================================${NC}"
    exit 1
else
    echo -e "${GREEN}  System Health Check PASSED. Environment is ready.${NC}"
    echo -e "${BOLD}${BLUE}=====================================================================${NC}"
    exit 0
fi
