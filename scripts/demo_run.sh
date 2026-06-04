#!/usr/bin/env bash
# demo_run.sh — SOVEREIGN Warhacker demo launcher (RTX 4060 Ti tower).
# Author: Yachay <yachay@szlholdings.dev> · DCO · ADDITIVE
# Doctrine v11 LOCKED (749/14/163) public.
#
# Boots a GPU-passthrough k3d cluster, deploys the cosign-signed UDS bundle,
# waits for the 7 flagship organs + local LLM, opens the operator shell, and
# prints the 3-command judge recipe. Run AFTER bootstrap_verify.sh passes.
#
#   ./demo_run.sh
set -euo pipefail

WORKDIR="${WORKDIR:-$HOME/szl-warhacker}"
CLUSTER="${CLUSTER:-szl-warhacker}"
PORT="${PORT:-8080}"
BUNDLE="${BUNDLE:-$WORKDIR/bundle.tar.zst}"
READY_TIMEOUT="${READY_TIMEOUT:-120}"   # seconds per organ

# The 5 flagship organs in szl-mesh:v0.4.0. namespace = szl-<organ>, deployment name = szl-<organ>.
# NOTE: vessels (phawaq) is deferred — no GHCR image published yet. hatun-mcp and local-llm
# are not in the v0.4.0 bundle. Remove from this list once phawaq image is published.
ORGANS=(szl-a11oy szl-sentra szl-amaru szl-rosie szl-killinchu)

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_hdr="\033[36m"; c_off="\033[0m"
say()  { printf "${c_hdr}==>${c_off} %s\n" "$*"; }
ok()   { printf "  ${c_ok}OK${c_off}   %s\n" "$*"; }
warn() { printf "  ${c_warn}WARN${c_off} %s\n" "$*"; }
die()  { printf "  ${c_err}FAIL${c_off} %s\n" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -s "$BUNDLE" ] || die "bundle not found at $BUNDLE — run bootstrap_verify.sh first."
[ -f "$WORKDIR/.llm_profile.env" ] && . "$WORKDIR/.llm_profile.env" || LLM_DESC="(profile unknown — run bootstrap_verify.sh)"

START_TS=$(date +%s)

# ---------------------------------------------------------------------------
# 1. Boot k3d cluster with GPU passthrough
# ---------------------------------------------------------------------------
say "1/5  k3d cluster '$CLUSTER' with GPU passthrough"
if k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"; then
  warn "cluster $CLUSTER already exists — reusing"
else
  # --gpus all requires the k3d image to carry the NVIDIA runtime; the bundle's
  # local-llm component tolerates the nvidia runtimeClass. Loadbalancer maps
  # host :$PORT -> ingress :80.
  k3d cluster create "$CLUSTER" \
      --gpus all \
      --port "${PORT}:80@loadbalancer" \
      --wait \
    || die "k3d cluster create failed (GPU passthrough). Check nvidia-container-toolkit."
fi
kubectl cluster-info >/dev/null 2>&1 && ok "cluster up; kube-context $(kubectl config current-context)"

# ---------------------------------------------------------------------------
# 2. Deploy the UDS bundle
# ---------------------------------------------------------------------------
say "2/5  uds deploy $BUNDLE"
uds deploy "$BUNDLE" --confirm || die "uds deploy failed"
ok "bundle deployed"

# ---------------------------------------------------------------------------
# 3. Wait for all organs Ready
# ---------------------------------------------------------------------------
say "3/5  Waiting for ${#ORGANS[@]} organs to be Ready (timeout ${READY_TIMEOUT}s each)"
for organ in "${ORGANS[@]}"; do
  # namespace == organ; deployment name == organ (UDS convention in this bundle)
  if kubectl -n "$organ" rollout status "deployment/$organ" --timeout="${READY_TIMEOUT}s" >/dev/null 2>&1; then
    ok "$organ Ready"
  elif kubectl wait --for=condition=Ready pod -l "app=$organ" -A --timeout="${READY_TIMEOUT}s" >/dev/null 2>&1; then
    ok "$organ Ready (by pod label)"
  else
    warn "$organ not Ready within ${READY_TIMEOUT}s — continuing (judge recipe still verifiable offline)"
  fi
done

# ---------------------------------------------------------------------------
# 4. Open the operator shell in the default browser
# ---------------------------------------------------------------------------
say "4/5  Opening operator shell http://localhost:${PORT}"
URL="http://localhost:${PORT}"
open_browser() {
  if   have xdg-open;  then xdg-open  "$1" >/dev/null 2>&1 &
  elif have firefox;   then firefox   "$1" >/dev/null 2>&1 &
  elif have google-chrome; then google-chrome "$1" >/dev/null 2>&1 &
  elif have chromium-browser; then chromium-browser "$1" >/dev/null 2>&1 &
  else warn "no browser found — open $1 manually"; return 1; fi
  return 0
}
open_browser "$URL" && ok "browser launched at $URL" || warn "open $URL manually"

ELAPSED=$(( $(date +%s) - START_TS ))

# ---------------------------------------------------------------------------
# 5. Judge verification recipe
# ---------------------------------------------------------------------------
say "5/5  Judge verification recipe"
cat <<RECIPE

  Demo ready in ${ELAPSED}s.  LLM organ: ${LLM_DESC}

  Hand the judge these 3 commands (run from $WORKDIR):

  1. cosign verify-blob --key cosign.pub --signature bundle.tar.zst.sig bundle.tar.zst
        -> Verified OK

  2. uds inspect oci://ghcr.io/szl-holdings/szl-mesh:v0.4.0
        -> szl-a11oy / szl-sentra / szl-amaru / szl-rosie / szl-killinchu packages (5 × sha256 refs)

  3. curl -X POST localhost:${PORT}/api/killinchu/v1/counter-uas/evaluate \\
        -d '{"track_id":"4840D6","lat":32.7,"lon":-117.2,"alt_m":120,"speed_ms":15}'
        -> DSSE-signed verdict + Khipu 3-of-4 consensus receipt

RECIPE
printf "${c_ok}Demo is live at %s${c_off}\n" "$URL"
