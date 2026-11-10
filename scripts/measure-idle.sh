#!/usr/bin/env bash
# scripts/measure-idle.sh
# ---------------------------------------------------------------------------
# Idle resource-footprint probe for SC-004.
#
#   Apple-silicon (macos-14 runner, task T064):       ≤ 1.0% CPU avg, ≤ 50 MB RSS
#   Intel 2018+   (macos-13 runner, task T064-intel): ≤ 2.0% CPU avg, ≤ 75 MB RSS
#
# Launches the built .app bundle, excludes a warm-up window, then samples CPU%
# (via `ps`) and RSS (via `ps`/`top`) once per second for the configured
# duration. Emits one CSV line on stdout:
#
#   avg_cpu_pct,peak_cpu_pct,avg_rss_mb,peak_rss_mb
#
# Exits 0 if both avg values are within budget, non-zero otherwise. A single
# per-second spike exceeding 2× the budget also fails the run (per spec §SC-004
# probe environment).
#
# Shared implementation — T064 invokes with defaults; T064-intel invokes as:
#   scripts/measure-idle.sh --duration 1200 --max-cpu 2.0 --max-rss 75
# ---------------------------------------------------------------------------

set -euo pipefail

DURATION=600            # seconds of measurement (after warm-up)
MAX_CPU="1.0"           # %, arithmetic mean of per-second samples
MAX_RSS=50              # MB, arithmetic mean of per-second samples
WARMUP=30               # seconds excluded from the mean
SPIKE_MULTIPLIER=2      # per-sample CPU ceiling as multiple of MAX_CPU
APP_PATH="${APP_PATH:-DerivedData/Build/Products/Debug/DynamicCaffeIsland.app}"
PROCESS_NAME="${PROCESS_NAME:-DynamicCaffeIsland}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration) DURATION="$2"; shift 2 ;;
        --max-cpu)  MAX_CPU="$2"; shift 2 ;;
        --max-rss)  MAX_RSS="$2"; shift 2 ;;
        --warmup)   WARMUP="$2"; shift 2 ;;
        --app)      APP_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^# ---*$/p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "measure-idle.sh: unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -d "$APP_PATH" ]]; then
    echo "measure-idle.sh: app bundle not found: $APP_PATH" >&2
    echo "  set APP_PATH or pass --app <path>" >&2
    exit 2
fi

# Launch the app (no Dock icon — LSUIElement=YES keeps it menubar-only)
open -n "$APP_PATH"
sleep 1
PID=$(pgrep -xn "$PROCESS_NAME" || true)
if [[ -z "$PID" ]]; then
    echo "measure-idle.sh: process '$PROCESS_NAME' not found after open -n" >&2
    exit 2
fi
trap 'kill "$PID" 2>/dev/null || true' EXIT

echo "probe pid=$PID duration=${DURATION}s warmup=${WARMUP}s budget=${MAX_CPU}%/${MAX_RSS}MB" >&2

# Warm-up excluded from the mean
sleep "$WARMUP"

sum_cpu=0; peak_cpu=0; spike_cpu=0
sum_rss=0; peak_rss=0
n=0
end=$(( $(date +%s) + DURATION ))
spike_ceiling=$(awk -v m="$MAX_CPU" -v k="$SPIKE_MULTIPLIER" 'BEGIN{printf "%.3f", m*k}')

while (( $(date +%s) < end )); do
    line=$(ps -o %cpu=,rss= -p "$PID" 2>/dev/null || true)
    if [[ -z "$line" ]]; then
        echo "measure-idle.sh: process $PID died during probe" >&2
        exit 2
    fi
    cpu=$(echo "$line" | awk '{print $1}')
    rss_kb=$(echo "$line" | awk '{print $2}')
    rss_mb=$(awk -v k="$rss_kb" 'BEGIN{printf "%.2f", k/1024}')

    sum_cpu=$(awk -v s="$sum_cpu" -v c="$cpu" 'BEGIN{printf "%.4f", s+c}')
    sum_rss=$(awk -v s="$sum_rss" -v r="$rss_mb" 'BEGIN{printf "%.4f", s+r}')
    peak_cpu=$(awk -v p="$peak_cpu" -v c="$cpu" 'BEGIN{printf "%.2f", (c>p)?c:p}')
    peak_rss=$(awk -v p="$peak_rss" -v r="$rss_mb" 'BEGIN{printf "%.2f", (r>p)?r:p}')

    # Detect > 2× budget spike (spec §SC-004)
    if awk -v c="$cpu" -v s="$spike_ceiling" 'BEGIN{exit !(c+0>s+0)}'; then
        spike_cpu=$(awk -v p="$spike_cpu" -v c="$cpu" 'BEGIN{printf "%.2f", (c>p)?c:p}')
    fi
    n=$((n+1))
    sleep 1
done

avg_cpu=$(awk -v s="$sum_cpu" -v n="$n" 'BEGIN{printf "%.3f", s/n}')
avg_rss=$(awk -v s="$sum_rss" -v n="$n" 'BEGIN{printf "%.2f", s/n}')

# CSV output on stdout
echo "${avg_cpu},${peak_cpu},${avg_rss},${peak_rss}"

fail=0
if awk -v a="$avg_cpu" -v m="$MAX_CPU" 'BEGIN{exit !(a+0>m+0)}'; then
    echo "FAIL: avg_cpu=${avg_cpu}% > max=${MAX_CPU}%" >&2
    fail=1
fi
if awk -v a="$avg_rss" -v m="$MAX_RSS" 'BEGIN{exit !(a+0>m+0)}'; then
    echo "FAIL: avg_rss=${avg_rss}MB > max=${MAX_RSS}MB" >&2
    fail=1
fi
if awk -v s="$spike_cpu" 'BEGIN{exit !(s+0>0)}'; then
    echo "FAIL: CPU spike=${spike_cpu}% exceeded ${SPIKE_MULTIPLIER}× budget (${spike_ceiling}%)" >&2
    fail=1
fi

exit "$fail"
