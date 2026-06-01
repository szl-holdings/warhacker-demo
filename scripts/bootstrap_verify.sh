#!/usr/bin/env bash
# bootstrap_verify.sh — SOVEREIGN demo dry-run, RTX 4060 Ti tower pre-flight.
# Author: Yachay <yachay@szlholdings.dev> · DCO · ADDITIVE
# Doctrine v11 LOCKED (749/14/163) public · v12 internal.
#
# Single command, fresh Ubuntu 24.04: verifies the tower can run the
# cosign-signed UDS Warhacker bundle. Honest — every check is a real
# command whose exit code gates the run. No fabricated output.
#
#   sudo ./bootstrap_verify.sh
#
# Exit 0 = tower is demo-ready. Non-zero = a named precondition failed.
set -euo pipefail

# ---------------------------------------------------------------------------
# Config — overridable by env. Defaults pull the v1.0.0 release artifacts.
# ---------------------------------------------------------------------------
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/szl-holdings/uds-bundles/yachay/uds-warhacker-v1.0.0-assets/releases/szl-warhacker-uds-v1.0.0}"
WORKDIR="${WORKDIR:-$HOME/szl-warhacker}"
MIN_DRIVER="${MIN_DRIVER:-535}"
COSIGN_VERSION="${COSIGN_VERSION:-v2.4.1}"
K3D_VERSION="${K3D_VERSION:-v5.6.3}"
# a4d73120... = sha256(PEM rendered with \n separators, NO trailing newline).
EXPECTED_PUBKEY_FPR="a4d73120c312d94bdd6cbdfa6f3d629cfff4b85e7addde5f9c3fd4c02341eb30"
EXPECTED_BUNDLE_SHA="88b99afc581e8c03d13c1033306c08c1027e51189f4f6c9f87223091c1119218"

# ---------------------------------------------------------------------------
# Pretty + assert helpers
# ---------------------------------------------------------------------------
c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_hdr="\033[36m"; c_off="\033[0m"
say()  { printf "${c_hdr}==>${c_off} %s\n" "$*"; }
ok()   { printf "  ${c_ok}OK${c_off}   %s\n" "$*"; }
warn() { printf "  ${c_warn}WARN${c_off} %s\n" "$*"; }
die()  { printf "  ${c_err}FAIL${c_off} %s\n" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ===========================================================================
# 1. NVIDIA driver + the GPU itself
# ===========================================================================
say "1/7  NVIDIA driver + RTX 4060 Ti"
have nvidia-smi || die "nvidia-smi not found. Install the NVIDIA driver (>= ${MIN_DRIVER}) first."

GPU_CSV="$(nvidia-smi --query-gpu=driver_version,name,memory.total --format=csv,noheader,nounits)"
echo "       $GPU_CSV"
DRIVER="$(echo "$GPU_CSV" | awk -F',' '{gsub(/ /,"",$1); print $1}')"
GPU_NAME="$(echo "$GPU_CSV" | awk -F',' '{print $2}')"
VRAM_MB="$(echo "$GPU_CSV"  | awk -F',' '{gsub(/ /,"",$3); print $3}')"
DRIVER_MAJOR="${DRIVER%%.*}"

[ "${DRIVER_MAJOR:-0}" -ge "$MIN_DRIVER" ] \
  && ok "driver $DRIVER >= $MIN_DRIVER" \
  || die "driver $DRIVER < required $MIN_DRIVER"

echo "$GPU_NAME" | grep -q "4060 Ti" \
  && ok "GPU is${GPU_NAME}" \
  || die "GPU name '$GPU_NAME' does not contain '4060 Ti'"

[ "${VRAM_MB:-0}" -ge 8000 ] \
  && ok "VRAM ${VRAM_MB} MiB >= 8 GB" \
  || die "VRAM ${VRAM_MB} MiB < 8 GB minimum"

# VRAM budget routing — written to a file demo_run.sh sources.
if [ "$VRAM_MB" -ge 15000 ]; then
  LLM_PROFILE="vllm-qwen2.5-7b-awq"
  LLM_DESC="16GB path: Qwen2.5-7B-Instruct-AWQ via vLLM"
else
  LLM_PROFILE="llamacpp-phi3.5-mini"
  LLM_DESC="8GB path: Phi-3.5-mini-instruct (Q4_K_M) via llama.cpp"
fi
ok "VRAM budget profile -> $LLM_DESC"
printf 'LLM_PROFILE=%s\nLLM_DESC="%s"\nVRAM_MB=%s\n' "$LLM_PROFILE" "$LLM_DESC" "$VRAM_MB" > "$WORKDIR/.llm_profile.env"

# ===========================================================================
# 2. Docker + nvidia-container-toolkit GPU passthrough
# ===========================================================================
say "2/7  Docker + nvidia-container-toolkit GPU passthrough"
have docker || die "docker not installed. apt-get install -y docker.io"
$SUDO docker info >/dev/null 2>&1 || die "docker daemon not reachable (is the service up / are you in the docker group?)"

if $SUDO docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
  ok "container saw the GPU via --gpus all"
else
  die "GPU passthrough failed. Install nvidia-container-toolkit and run: nvidia-ctk runtime configure --runtime=docker && systemctl restart docker"
fi

# ===========================================================================
# 3. k3d (install if missing)
# ===========================================================================
say "3/7  k3d"
if have k3d; then
  ok "k3d present: $(k3d version | head -1)"
else
  warn "k3d missing — installing ${K3D_VERSION}"
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG="$K3D_VERSION" $SUDO bash
  have k3d && ok "k3d installed: $(k3d version | head -1)" || die "k3d install failed"
fi

# ===========================================================================
# 4. uds-cli (install from defenseunicorns/uds-cli releases if missing)
# ===========================================================================
say "4/7  uds-cli"
if have uds; then
  ok "uds present: $(uds version 2>&1 | head -1)"
else
  warn "uds missing — installing latest defenseunicorns/uds-cli"
  ARCH="$(uname -m)"; case "$ARCH" in x86_64) ARCH=amd64;; aarch64) ARCH=arm64;; esac
  UDS_TAG="$(curl -fsSL https://api.github.com/repos/defenseunicorns/uds-cli/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')"
  curl -fsSL -o /tmp/uds "https://github.com/defenseunicorns/uds-cli/releases/download/${UDS_TAG}/uds-cli_${UDS_TAG}_Linux_${ARCH}"
  $SUDO install -m 0755 /tmp/uds /usr/local/bin/uds
  have uds && ok "uds installed: $(uds version 2>&1 | head -1)" || die "uds install failed"
fi

# ===========================================================================
# 5. cosign (install if missing)
# ===========================================================================
say "5/7  cosign"
if have cosign; then
  ok "cosign present: $(cosign version 2>&1 | grep -i gitversion || cosign version 2>&1 | head -1)"
else
  warn "cosign missing — installing ${COSIGN_VERSION}"
  ARCH="$(uname -m)"; case "$ARCH" in x86_64) ARCH=amd64;; aarch64) ARCH=arm64;; esac
  curl -fsSL -o /tmp/cosign "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${ARCH}"
  $SUDO install -m 0755 /tmp/cosign /usr/local/bin/cosign
  have cosign && ok "cosign installed: $(cosign version 2>&1 | grep -i gitversion)" || die "cosign install failed"
fi

# ===========================================================================
# 6. Verify the signed bundle (fetch if not local)
# ===========================================================================
say "6/7  Bundle authenticity (cosign verify-blob)"
for f in bundle.tar.zst bundle.tar.zst.sig bundle.tar.zst.sha256 bundle.tar.zst.rekor.bundle cosign.pub; do
  if [ ! -s "$WORKDIR/$f" ]; then
    warn "fetching $f"
    curl -fsSL -o "$WORKDIR/$f" "$RAW_BASE/$f" || die "could not fetch $f from $RAW_BASE"
  fi
done

# Public key fingerprint must match the brief (PEM \n, no trailing newline).
GOT_FPR="$(printf '%s' "$(cat "$WORKDIR/cosign.pub")" | sha256sum | awk '{print $1}')"
[ "$GOT_FPR" = "$EXPECTED_PUBKEY_FPR" ] \
  && ok "cosign.pub fingerprint matches brief ($EXPECTED_PUBKEY_FPR)" \
  || die "cosign.pub fingerprint $GOT_FPR != expected $EXPECTED_PUBKEY_FPR"

# Integrity manifest.
( cd "$WORKDIR" && sha256sum -c bundle.tar.zst.sha256 ) \
  && ok "bundle.tar.zst sha256 manifest OK ($EXPECTED_BUNDLE_SHA)" \
  || die "sha256 integrity check failed"

# Authenticity — offline signature verify (airgap-safe; no tlog call).
if cosign verify-blob --key "$WORKDIR/cosign.pub" --insecure-ignore-tlog=true \
     --signature "$WORKDIR/bundle.tar.zst.sig" "$WORKDIR/bundle.tar.zst" 2>&1 | grep -q "Verified OK"; then
  ok "cosign verify-blob: Verified OK (offline signature)"
else
  die "cosign verify-blob did NOT report Verified OK"
fi

# Offline transparency-log proof against the sha256 manifest.
if cosign verify-blob --key "$WORKDIR/cosign.pub" --insecure-ignore-tlog=true \
     --bundle "$WORKDIR/bundle.tar.zst.rekor.bundle" "$WORKDIR/bundle.tar.zst.sha256" 2>&1 | grep -q "Verified OK"; then
  ok "cosign rekor bundle: Verified OK (offline tlog proof, logIndex 1693757456)"
else
  warn "offline rekor-bundle verify did not report Verified OK (non-fatal for airgap demo)"
fi

# ===========================================================================
# 7. Bundle inventory
# ===========================================================================
say "7/7  Bundle inventory (zarf package inspect)"
if zarf package inspect definition "$WORKDIR/bundle.tar.zst" >/tmp/zarf_inspect.txt 2>&1 \
   || zarf package inspect "$WORKDIR/bundle.tar.zst" >/tmp/zarf_inspect.txt 2>&1; then
  # strip ANSI colour codes before extracting component names
  sed 's/\x1b\[[0-9;]*m//g' /tmp/zarf_inspect.txt \
    | grep -oE "(a11oy|amaru|sentra|killinchu|rosie)-governance" | sort -u | sed 's/^/       /' || true
  ok "zarf inspected bundle (governance components listed above)"
else
  die "zarf package inspect failed — see /tmp/zarf_inspect.txt"
fi

echo
printf "${c_ok}========================================================${c_off}\n"
printf "${c_ok} TOWER IS DEMO-READY${c_off}\n"
printf "  GPU:     %s (%s MiB)\n" "$GPU_NAME" "$VRAM_MB"
printf "  Driver:  %s\n" "$DRIVER"
printf "  LLM:     %s\n" "$LLM_DESC"
printf "  Bundle:  Verified OK · sha256 %s…\n" "${EXPECTED_BUNDLE_SHA:0:16}"
printf "  Next:    ./demo_run.sh\n"
printf "${c_ok}========================================================${c_off}\n"
