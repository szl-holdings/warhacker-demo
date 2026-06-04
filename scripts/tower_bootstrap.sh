#!/usr/bin/env bash
# SZL Warhacker Tower Bootstrap — RTX 4060 Ti tower, June 9 rehearsal
# One-shot installer for every prerequisite to deploy szl-mesh:v0.4.0 on a local k3d cluster.
# Usage: bash tower_bootstrap.sh   (run on the tower; needs sudo for Docker + NVIDIA toolkit)
# Idempotent: safe to re-run. Pinned versions match the bundle's tooling.
set -euo pipefail

log(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# ---- Versions (pinned to match szl-mesh:v0.4.0 build) ----
K3D_VER="v5.8.3"
KUBECTL_VER="v1.30.2"
UDS_CLI_VER="v0.32.0"     # bundles Zarf v0.77.0 — matches the bundle
COSIGN_VER="v2.4.1"
ARCH="amd64"

log "0/8 Preflight"
uname -a
have nvidia-smi && nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || echo "WARN: nvidia-smi not found — GPU organs will be CPU-only"

log "1/8 Docker"
if ! have docker; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
  echo "NOTE: log out/in (or 'newgrp docker') for group to take effect"
fi
docker --version || true

log "2/8 NVIDIA Container Toolkit (GPU in k3d)"
if have nvidia-smi && ! docker info 2>/dev/null | grep -qi nvidia; then
  distribution=$(. /etc/os-release; echo "$ID$VERSION_ID")
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg || true
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null || true
  sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit || echo "WARN: NVIDIA toolkit install failed — continue CPU-only"
  sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker || true
fi

log "3/8 k3d ${K3D_VER}"
if ! have k3d || [ "$(k3d version 2>/dev/null | grep -o 'v5\.[0-9.]*' | head -1)" != "$K3D_VER" ]; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG="$K3D_VER" bash
fi
k3d version || true

log "4/8 kubectl ${KUBECTL_VER}"
if ! have kubectl; then
  curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/${ARCH}/kubectl"
  sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl
fi
kubectl version --client || true

log "5/8 uds-cli ${UDS_CLI_VER}"
if ! have uds || [ "$(uds version 2>/dev/null)" != "${UDS_CLI_VER#v}" ]; then
  curl -fsSLO "https://github.com/defenseunicorns/uds-cli/releases/download/${UDS_CLI_VER}/uds-cli_${UDS_CLI_VER}_Linux_${ARCH}"
  sudo install -m 0755 "uds-cli_${UDS_CLI_VER}_Linux_${ARCH}" /usr/local/bin/uds
  rm -f "uds-cli_${UDS_CLI_VER}_Linux_${ARCH}"
fi
uds version || true

log "6/8 cosign ${COSIGN_VER} (verify signed images)"
if ! have cosign; then
  curl -fsSLO "https://github.com/sigstore/cosign/releases/download/${COSIGN_VER}/cosign-linux-${ARCH}"
  sudo install -m 0755 "cosign-linux-${ARCH}" /usr/local/bin/cosign && rm -f "cosign-linux-${ARCH}"
fi
cosign version || true

log "7/8 Verify a flagship image signature (proof the supply chain works)"
cosign verify ghcr.io/szl-holdings/a11oy:uds-v0.2.0 \
  --certificate-identity-regexp="^https://github.com/szl-holdings/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" 2>/dev/null \
  && echo "✅ a11oy image signature verified (SLSA L1 honest, cosign-signed)" \
  || echo "WARN: cosign verify failed (network/policy) — retry after cluster is up"

log "8/8 DONE — deploy the mesh"
cat <<'NEXT'
Tower is ready. To deploy the SZL mesh:

  # create a GPU-enabled k3d cluster
  k3d cluster create szl --gpus 1 || k3d cluster create szl

  # deploy the signed bundle (from USB or GHCR)
  uds deploy oci://ghcr.io/szl-holdings/szl-mesh:v0.4.0 --confirm
  # (USB path: uds-cli bundle deploy szl-mesh-v0.4.0.tar.zst --confirm)

  # verify organs
  kubectl get pods -A | grep -E 'a11oy|sentra|amaru|rosie|killinchu'

  # counter-UAS demo
  curl -X POST localhost:8080/api/killinchu/v1/counter-uas/evaluate \
    -d '{"track_id":"4840D6","lat":32.7,"lon":-117.2,"alt_m":120,"speed_ms":15}'

  # kill-move (3-of-4 Khipu quorum)
  bash warhacker-demo/scripts/kill_organ.sh sentra      # CANONICAL (f=1 tolerated)
NEXT
