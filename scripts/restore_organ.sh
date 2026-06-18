#!/usr/bin/env bash
# restore_organ.sh — inverse of kill_organ.sh. Scales an organ back to 1.
# Author: Yachay <yachay@szlholdings.dev> · DCO · ADDITIVE
#
#   ./restore_organ.sh sentra
set -euo pipefail

ORGAN="${1:-}"
VALID="sentra amaru a11oy killinchu rosie"
usage() { echo "usage: $0 <organ>   (one of: $VALID)"; exit 2; }
[ -n "$ORGAN" ] || usage
echo " $VALID " | grep -q " $ORGAN " || { echo "unknown organ '$ORGAN'"; usage; }

c_ok="\033[32m"; c_off="\033[0m"

# namespace = szl-<organ>; deployment name = szl-<organ> (matches kill_organ.sh / the bundle)
NS="szl-${ORGAN}"
DEPLOY="szl-${ORGAN}"
echo "==> restoring organ: $ORGAN (namespace: $NS, scale deployment/$DEPLOY -> 1)"
kubectl -n "$NS" scale "deployment/$DEPLOY" --replicas=1
kubectl -n "$NS" rollout status "deployment/$DEPLOY" --timeout=120s

LIVE=0
for w in a11oy sentra amaru killinchu; do
  r="$(kubectl -n "szl-$w" get "deployment/szl-$w" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  [ "${r:-0}" != "0" ] && LIVE=$((LIVE+1))
done
printf "${c_ok}==> $ORGAN restored. Khipu witnesses live: ${LIVE}-of-4 (threshold=3).${c_off}\n"
