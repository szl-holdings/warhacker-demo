# warhacker-demo

> ⚠️ **STAGING — not production-grade.** This repository is a demo/dry-run surface and should not be treated as a production deployment.

SOVEREIGN demo dry-run for the NVIDIA RTX 4060 Ti tower (Warhacker, June 16–19).
One command verifies the tower; one command runs the demo. Real shell scripts —
nothing narrative.

**Author:** Yachay `<yachay@szlholdings.dev>` · DCO · ADDITIVE
**Doctrine:** v11 LOCKED public — **749 / 14 / 163** (declarations / unique axioms / tracked sorries)
**License:** Apache-2.0
**Consumes:** the cosign-signed bundle from
[`szl-warhacker-uds-v1.0.0`](https://github.com/szl-holdings/uds-bundles/releases/tag/szl-warhacker-uds-v1.0.0).

---

## Cold-boot-to-demo recipe

On a fresh Ubuntu 24.04 tower with the NVIDIA driver (≥ 535) already installed:

```bash
git clone https://github.com/szl-holdings/warhacker-demo
cd warhacker-demo/scripts

# 1. Pre-flight: driver, GPU, docker GPU passthrough, k3d, uds, cosign,
#    and a real cosign verify of the signed bundle. Installs missing tools.
sudo ./bootstrap_verify.sh
#    -> TOWER IS DEMO-READY

# 2. Run the demo: GPU k3d cluster, deploy the bundle, wait for 8 organs,
#    open the operator shell, print the 3-command judge recipe.
./demo_run.sh
#    -> Demo is live at http://localhost:8080

# 3. (optional) Thermal guard daemon for the duration of the pitch
./thermal_guard.sh &
```

Target: **cold boot to demo-ready in under 90 seconds** once tools are cached
(k3d cluster ~15–25 s + `uds deploy` ~30–45 s + organ readiness ~10–20 s).
First-ever run is longer because k3d/uds/cosign install and the local-LLM image
warms; budget several minutes once, then it is cached on the tower.

---

## Scripts

| Script | What it does |
|---|---|
| `scripts/bootstrap_verify.sh` | Fresh-tower pre-flight. Asserts driver ≥ 535, GPU name contains `4060 Ti`, VRAM ≥ 8 GB; routes the LLM profile (16 GB → Qwen2.5-7B-AWQ/vLLM, 8 GB → Phi-3.5-mini/llama.cpp); checks docker GPU passthrough; installs k3d / uds-cli / cosign if missing; `cosign verify-blob` → **Verified OK**; `zarf package inspect`. |
| `scripts/demo_run.sh` | `k3d cluster create szl-warhacker --gpus all --port 8080:80@loadbalancer`; `uds deploy bundle.tar.zst --confirm`; waits for a11oy, amaru, sentra, rosie, killinchu, vessels, hatun-mcp, local-llm; opens `localhost:8080`; prints the 3-command judge recipe. |
| `scripts/airgap_test.sh` | Loopback-only network namespace; runs the offline verification + 4-organ chain inside it; asserts no DNS, no HTTP, no Rekor push; exits 0 iff airgap holds, 1 with diagnostics otherwise. |
| `scripts/thermal_guard.sh` | Background daemon. Polls GPU temp every 1 s; **WARN at 80 °C** (logs only), **THROTTLE at 85 °C** via `nvidia-smi -lgc 1500,2000`. Demo continues; warnings stay in the log file. |
| `scripts/kill_organ.sh` | The demo kill-move. `kill_organ.sh <organ>` scales that deployment to 0 and reports live witness count. Kill 1 → 3-of-4 (canonical); kill 2 → 2-of-4 (REJECTED). |
| `scripts/restore_organ.sh` | Inverse — scales an organ back to 1. |

---

## The 8 organs

The 7 flagship organs plus the local-LLM organ, all behind the operator shell:

`a11oy` · `amaru` · `sentra` · `rosie` · `killinchu` · `vessels` · `hatun-mcp` · `local-llm`

Four of them (a11oy, sentra, amaru, killinchu) are the **Khipu Consensus** witnesses:
an action is canonical only with **≥ 3-of-4** independent DSSE signatures over the same
`action_hash`. The protocol tolerates **f = 1** failed witness. See
[`khipu-consensus`](https://github.com/szl-holdings/khipu-consensus).

---

## Fixtures

`fixtures/` carries the **real** signed v1.0.0 artifacts (≈ 32 KB total), so the
verification path is testable without network:

```
bundle.tar.zst            bundle SHA256 88b99afc…1119218 (matches the release)
bundle.tar.zst.sig        ECDSA-P256, cosign v2.4.1
bundle.tar.zst.sha256     integrity manifest
bundle.tar.zst.rekor.bundle  offline Sigstore tlog proof (logIndex 1693757456)
cosign.pub                fingerprint a4d73120…2341eb30
PROOF.md                  upstream proof from the UDS Finish ledger
```

Verify the fixtures offline:

```bash
cd fixtures
sha256sum -c bundle.tar.zst.sha256
cosign verify-blob --key cosign.pub --signature bundle.tar.zst.sig bundle.tar.zst   # Verified OK
```

For the full-size, image-embedding airgap bundle (`airgap-bundle.tar.zst`,
logIndex 1693866388) pull from the release; it is too large to live in-repo.

---

## Hardware target

| | 4060 Ti 16 GB | 4060 Ti 8 GB |
|---|---|---|
| LLM organ | Qwen2.5-7B-Instruct-AWQ via vLLM | Phi-3.5-mini-instruct (Q4_K_M) via llama.cpp |
| Driver | ≥ 535 | ≥ 535 |
| VRAM assert | ≥ 8 GB (16 GB → vLLM path) | ≥ 8 GB |

`bootstrap_verify.sh` writes the chosen profile to `~/szl-warhacker/.llm_profile.env`,
which `demo_run.sh` sources.

---

## Doctrine note

v11 (**749/14/163**) is the public LOCKED doctrine and the canonical numbers for this demo. Doctrine v11 749/14/163 at kernel commit `c7c0ba17` — Λ = Conjecture 1 (not a theorem) · SLSA L1 honest.
