#!/usr/bin/env bash
# kill_organ.sh — the Warhacker demo kill-move.
# Author: Yachay <yachay@szlholdings.dev> · DCO · ADDITIVE
# Doctrine v11 LOCKED (749/14/163) public.
#
# Scales one flagship organ deployment to 0 replicas to demonstrate Khipu
# Consensus BFT 3-of-4 safety:
#   kill 1 organ -> 3-of-4 witnesses sign -> action CANONICAL (quorum holds)
#   kill 2 organs -> 2-of-4 witnesses    -> action REJECTED (quorum lost)
#
#   ./kill_organ.sh sentra
#   ./restore_organ.sh sentra   # inverse
set -euo pipefail

ORGAN="${1:-}"
VALID="sentra amaru a11oy killinchu rosie"

usage() { echo "usage: $0 <organ>   (one of: $VALID)"; exit 2; }
[ -n "$ORGAN" ] || usage
echo " $VALID " | grep -q " $ORGAN " || { echo "unknown organ '$ORGAN'"; usage; }

c_ok="\033[32m"; c_err="\033[31m"; c_off="\033[0m"

# namespace == deployment name == organ (UDS bundle convention)
echo "==> killing organ: $ORGAN (scale deployment/$ORGAN -> 0)"
kubectl -n "$ORGAN" scale "deployment/$ORGAN" --replicas=0

# Block until scale-down completes (0 ready replicas).
echo "    waiting for $ORGAN to reach 0 ready replicas..."
for _ in $(seq 1 60); do
  READY="$(kubectl -n "$ORGAN" get "deployment/$ORGAN" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  READY="${READY:-0}"
  [ "$READY" = "0" ] && break
  sleep 1
done

READY="$(kubectl -n "$ORGAN" get "deployment/$ORGAN" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
READY="${READY:-0}"
if [ "$READY" = "0" ]; then
  printf "${c_ok}    $ORGAN is DOWN (0 replicas). Witness offline.${c_off}\n"
else
  printf "${c_err}    $ORGAN still has $READY ready replicas — scale-down incomplete.${c_off}\n"
  exit 1
fi

# Count remaining live witnesses among the 4 consensus organs (a11oy/sentra/amaru/killinchu).
LIVE=0
for w in a11oy sentra amaru killinchu; do
  r="$(kubectl -n "$w" get "deployment/$w" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  [ "${r:-0}" != "0" ] && LIVE=$((LIVE+1))
done

echo "==> Khipu Consensus witnesses live: ${LIVE}-of-4 (threshold=3)"
if [ "$LIVE" -ge 3 ]; then
  printf "${c_ok}    ${LIVE}-of-4 >= 3  ->  action CANONICAL (BFT tolerates f=1).${c_off}\n"
else
  printf "${c_err}    ${LIVE}-of-4 <  3  ->  action REJECTED (quorum lost — fail CLOSED).${c_off}\n"
fi
