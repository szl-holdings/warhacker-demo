<!-- szl-investor-header -->
<div align="center">

# warhacker-demo

### A one-command **SOVEREIGN dry-run** that stands up the full SZL governed-AI substrate on a single air-gapped tower — and proves, with signed receipts, that an autonomous AI was caught the moment it crossed a line.

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square)](LICENSE)
[![Doctrine v11 LOCKED](https://img.shields.io/badge/Doctrine-v11_LOCKED_749%2F14%2F163-d4a444?style=flat-square)](https://github.com/szl-holdings/lutar-lean/commit/c7c0ba17)
[![Λ Conjecture 1](https://img.shields.io/badge/Λ-Conjecture_1_(not_a_theorem)-3b82f6?style=flat-square)](https://github.com/szl-holdings/lutar-lean)
[![SLSA L1 honest](https://img.shields.io/badge/SLSA-L1_honest-22c55e?style=flat-square)](https://slsa.dev/spec/v1.0/levels)
[![UDS Core ≥1.5.0](https://img.shields.io/badge/UDS_Core-≥1.5.0-7c3aed?style=flat-square)](https://uds.defenseunicorns.com/)

[Live demo board](https://szlholdings-killinchu.hf.space/elite) · [a11oy warhacker tab](https://szlholdings-a11oy.hf.space/warhacker) · [Docs](https://szl-holdings.github.io/docs-site) · [SZL Holdings](https://a11oy.net)

</div>

## 💡 Why it matters

Cannonico's Warhacker problem is blunt: when an autonomous drone loses contact mid-mission, *no one can answer whether the AI is still inside authorized parameters or has gone off script.* This repo is the reproducible proof that the SZL substrate answers that question **on a single sovereign tower, fully air-gapped** — independently monitoring AI behavior, catching the moment a line is crossed, and backing it with a permanent, tamper-evident record. The bar at [Defense Unicorns Warhacker](https://defenseunicorns.com/warhacker/) is *BUILD → PACKAGE → DEPLOY into a mission environment*, not a slide. This is the deploy.

## ▶️ Live demo

The interactive 5-problem × 5-demo board runs live today:

- **Counter-UAS elite board:** [szlholdings-killinchu.hf.space/elite](https://szlholdings-killinchu.hf.space/elite)
- **a11oy command-platform warhacker tab:** [szlholdings-a11oy.hf.space/warhacker](https://szlholdings-a11oy.hf.space/warhacker)

Each demo runs a **real, in-image, pure-Python mechanism** (Merkle root · RFC-6962 inclusion proof · SHA-256 hash chain · point-in-polygon geofence · conformal prediction interval · CPA/TCPA closest-approach), emits a real `perf_counter` step timeline, runs an **always-on single-byte tamper negative test** that cryptographically breaks the signed Merkle chain, and produces a signed **DSSE / ECDSA-P256 Khipu receipt**.

## ⚡ Quick start (one command)

```bash
git clone https://github.com/szl-holdings/warhacker-demo.git
cd warhacker-demo
make tower-verify        # full sovereign dry-run on this machine, air-gap-safe
```

`make tower-verify` is designed for a single self-hosted tower (validated on an **NVIDIA RTX 4060 Ti** workstation): it provisions a local **k3d** cluster, deploys the SZL **UDS** bundle on top of UDS Core, runs the air-gap reachability test, exercises the **thermal guard**, and executes the **Khipu 3-of-4 quorum kill-move** — then prints a signed pass/fail receipt. No external network is required after image pull.

## 🔍 How it works

The substrate enforces policy and emits signed, replayable audit receipts so every AI action can be verified after the fact. The drone-oversight loop (problem **P1 CANNONICO**, labelled **REAL TODAY**) independently watches the autonomous agent and, when an authorized envelope is breached, halts the action and writes a tamper-evident receipt to a hash-linked Merkle DAG. The remaining four problem families (Tychee, HANGAR2APPS, Cyber-RTS, Raven) run the **same proven horizontal substrate on clearly-labelled sample data** — they are **ROADMAP**, not claimed as fielded capability.

---

<details>
<summary><strong>📐 Full technical detail, the 25 demos, and the honesty boundary</strong></summary>

## The 25 demos (5 problems × 5)

| Problem | Key | Status | Demos |
|---|---|---|---|
| **P1 CANNONICO** — drone AI oversight | `cannonico` | **REAL TODAY** | C1 Altitude-Envelope Breach · C2 Geofence Keep-Out Incursion · C3 AI-Confidence Collapse · C4 Comms-Loss Autonomous Drift · C5 Tampered Flight-Log Detection |
| **P2 TYCHEE** — satellite ground software | `tychee` | ROADMAP · substrate-real | T1 Orbital Conjunction · T2 Satellite-Health Anomaly · T3 Command Verification (3-of-4 Byzantine) · T4 Δv Maneuver STL · T5 Ground-SW Replay Determinism |
| **P3 HANGAR2APPS** — deployment health screening | `hangar2apps` | ROADMAP · substrate-real | H1 Vital-Sign Anomaly (conformal) · H2 Clinical Tipping-Point · H3 Health-Record Summarization · H4 Tamper-Proof Medical-Record Chain · H5 Offline / Sovereign Edge Screening |
| **P4 CYBER-RTS** — trajectory / orbit viz | `cyber_rts` | ROADMAP · substrate-real | CR1 Orbital Engagement Geometry · CR2 Space-Domain-Awareness Galaxy · CR3 RF Signal Attribution · CR4 Trajectory Conformal Tube · CR5 Byzantine Consensus |
| **P5 RAVEN** — AI at the tactical edge | `raven` | ROADMAP · substrate-real | R1 Boids Swarm · R2 Sensor-Fusion Ellipse · R3 Mesh-Network Graph · R4 Cascade Tree · R5 Tactical Galaxy |

The nominal/tamper toggle is real: for the tamper-evident chains (e.g. `hangar2apps/H4`), a single flipped byte moves `merkle_match` from `True` → `False` and surfaces **TAMPER DETECTED at session #N** with the exact break index.

## What the tower dry-run actually verifies

| Stage | Mechanism | Pass condition |
|---|---|---|
| **k3d + UDS deploy** | Local k3d cluster, SZL bundle on UDS Core (`>=1.5.0`), Zarf (`>=0.77.0`) | All pods Ready; `Package` CR reconciled |
| **Air-gap test** | Egress blocked; app runs from vendored libs only (zero runtime CDN) | Demos serve with no outbound network |
| **Thermal guard** | Tower thermal envelope watched during load | No throttle/over-temp during run |
| **Khipu 3-of-4 kill-move** | Byzantine quorum halts a non-compliant action | Action halted; signed receipt emitted |

## Honesty boundary (binding — verified, never inflated)

- **Λ = Conjecture 1, never a theorem.** The *unconditional* uniqueness claim is machine-checked **false** (`Round13.maxAgg_ne_Lambda` counterexample); only the **conditional** CUT-2 slice-multiplicativity uniqueness is proven (`lambda_unique_of_separable`, axiom-free, 0 sorry, CI-green). See [lutar-lean](https://github.com/szl-holdings/lutar-lean).
- **Proven PURIQ formulas = exactly 5** {F1, F11, F12, F18, F19} — kernel-verified, axiom-free (`Lutar.Wave8.AxiomDisclosure.locked_count_five` proves the count `= 5` by `decide`). The broader experimental `main` corpus (≈1323 decls / 23 axioms / CI-green) is reported **separately** and is **never folded into the locked 5**.
- **Byzantine BFT optimality = Khipu Conjecture 2 (OPEN).**
- **Supply chain: SLSA Build L1 honest** (cosign keyless-signed, Rekor-anchored). L2 verified-provenance is on the **roadmap**; bundle-level attestation is **not yet earned**. **L3 / FedRAMP / Iron Bank / CMMC are never claimed.**
- **CANNONICO is the only family labelled REAL TODAY.** The other four demonstrate the same substrate on clearly-labelled sample data and are explicitly **ROADMAP**.
- No fabricated metrics; no inflated proof counts.

## Event context

Defense Unicorns **Warhacker**: 16–19 June 2026, San Diego, CA — a build/package/deploy hackathon whose stated success measure is *number of apps in mission environments*, packaged on open-source **UDS Core** for rapid deployment anywhere, cloud to edge ([Defense Unicorns — Warhacker](https://defenseunicorns.com/warhacker/)). The five challenge problems above are the published owners' asks.

## Non-affiliation

SZL Holdings is **not affiliated with, endorsed by, or sponsored by Defense Unicorns**. "UDS", "UDS Core", and "Defense Unicorns" are names/marks of Defense Unicorns, referenced here only to describe interoperability. This repo deploys an SZL-authored UDS bundle on top of the open-source **UDS Core** platform; UDS Core (AGPL-3.0) is followed **pattern-only** — never forked or adopted. See [`NOTICE`](NOTICE).

</details>

<!-- szl-doctrine-footer -->

---

### Cross-references

- **Formal proofs / kernel:** [lutar-lean](https://github.com/szl-holdings/lutar-lean) (kernel `c7c0ba17`)
- **Command platform:** [a11oy](https://github.com/szl-holdings/a11oy) · **Counter-UAS / drones:** [killinchu](https://github.com/szl-holdings/killinchu)
- **Deployment bundles:** [uds-bundles](https://github.com/szl-holdings/uds-bundles) · [szl-uds-deployment](https://github.com/szl-holdings/szl-uds-deployment)
- **Receipts corpus:** [szl-lake](https://github.com/szl-holdings/szl-lake) · **Papers / doctrine:** [szl-papers](https://github.com/szl-holdings/szl-papers)

<sub>Λ Conjecture 1 (not a theorem) · locked-proven = exactly 5 {F1,F11,F12,F18,F19} · experimental main ≈1323/23 reported separately · 749/14/163 v11 LOCKED (kernel `c7c0ba17`) · SLSA L1 honest · L2 verified-provenance on roadmap · no FedRAMP / Iron Bank / CMMC · [SZL Holdings](https://a11oy.net) · Apache-2.0</sub>

