#!/usr/bin/env bash
# thermal_guard.sh — background GPU thermal daemon for the Warhacker demo.
# Author: Yachay <yachay@szlholdings.dev> · DCO · ADDITIVE
#
# Polls GPU temperature every second. Logs a WARN at 80C; at 85C it clamps
# the graphics clock via `nvidia-smi -lgc 1500,2000` so the demo keeps running
# instead of thermal-throttling unpredictably mid-pitch. All output goes to a
# log file — the judge never sees a warning on screen.
#
#   ./thermal_guard.sh &                 # start in background
#   THERMAL_LOG=/tmp/t.log ./thermal_guard.sh &
#   kill $(cat /tmp/thermal_guard.pid)   # stop
set -uo pipefail

WARN_C="${WARN_C:-80}"
THROTTLE_C="${THROTTLE_C:-85}"
INTERVAL="${INTERVAL:-1}"
THERMAL_LOG="${THERMAL_LOG:-$HOME/szl-warhacker/thermal_guard.log}"
PIDFILE="${PIDFILE:-/tmp/thermal_guard.pid}"
GPU_ID="${GPU_ID:-0}"

mkdir -p "$(dirname "$THERMAL_LOG")"
echo $$ > "$PIDFILE"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$THERMAL_LOG"; }

command -v nvidia-smi >/dev/null 2>&1 || { echo "nvidia-smi not found" >&2; exit 2; }

# Clean up clock lock on exit so the GPU returns to normal.
cleanup() {
  log "thermal_guard stopping — resetting GPU clocks (-rgc)"
  nvidia-smi -i "$GPU_ID" -rgc >/dev/null 2>&1 || true
  rm -f "$PIDFILE"
}
trap cleanup EXIT INT TERM

log "thermal_guard start (warn=${WARN_C}C throttle=${THROTTLE_C}C interval=${INTERVAL}s gpu=${GPU_ID})"

THROTTLED=0
while true; do
  TEMP="$(nvidia-smi -i "$GPU_ID" --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')"
  if [ -z "$TEMP" ]; then log "WARN could not read temperature"; sleep "$INTERVAL"; continue; fi

  if [ "$TEMP" -ge "$THROTTLE_C" ]; then
    if [ "$THROTTLED" -eq 0 ]; then
      log "THROTTLE ${TEMP}C >= ${THROTTLE_C}C — clamping graphics clock (nvidia-smi -lgc 1500,2000)"
      nvidia-smi -i "$GPU_ID" -lgc 1500,2000 >> "$THERMAL_LOG" 2>&1 || log "WARN -lgc failed (needs root / persistence mode)"
      THROTTLED=1
    fi
  elif [ "$TEMP" -ge "$WARN_C" ]; then
    log "WARN ${TEMP}C >= ${WARN_C}C"
  else
    # Cooled back down — release the clamp once.
    if [ "$THROTTLED" -eq 1 ] && [ "$TEMP" -lt "$((WARN_C - 5))" ]; then
      log "RECOVER ${TEMP}C — releasing clock clamp (-rgc)"
      nvidia-smi -i "$GPU_ID" -rgc >> "$THERMAL_LOG" 2>&1 || true
      THROTTLED=0
    fi
  fi
  sleep "$INTERVAL"
done
