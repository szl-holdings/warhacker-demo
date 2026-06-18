# SZL UDS — Warhacker Judge Proof Packet

**Author:** Yachay `<yachay@szlholdings.dev>` · DCO · ADDITIVE
**Bundle:** `szl-warhacker-uds-v1.0.0` · built with zarf v0.51.0 · cosign v2.4.1
*(tower deploys it via uds-cli v0.32.0 / Zarf v0.77.0 — see `scripts/tower_bootstrap.sh`; signed digest unchanged)*
**Doctrine:** v11 LOCKED public — **749 declarations / 14 unique axioms / 163 tracked sorries**

---

## 1. Three commands you can run

Run from the demo tower (`~/szl-warhacker`). Each prints its own pass line.

```bash
# 1. Authenticity — offline ECDSA-P256 signature verify
cosign verify-blob --key cosign.pub --signature bundle.tar.zst.sig bundle.tar.zst
#   -> Verified OK

# 2. Contents — what is inside the signed bundle
zarf package inspect bundle.tar.zst
#   -> a11oy / amaru / sentra / killinchu / rosie governance components

# 3. Live chain — one mission through the organs
curl -X POST localhost:8080/api/killinchu/uds/v1/mission/execute \
  -d '{"action":"threat_assess","payload":{"track_id":"4840D6"}}'
#   -> DSSE-signed verdict + Khipu 3-of-4 consensus receipt
```

Integrity equivalent: `sha256sum -c bundle.tar.zst.sha256` → `bundle.tar.zst: OK`.

---

## 2. Public transparency-log receipts (Sigstore Rekor)

These were anchored in the public log before Warhacker; anyone can open them:

- Governance bundle: **logIndex 1693757456** — <https://search.sigstore.dev/?logIndex=1693757456>
- Airgap image bundle: **logIndex 1693866388** — <https://search.sigstore.dev/?logIndex=1693866388>

API check: `curl "https://rekor.sigstore.dev/api/v1/log/entries?logIndex=1693757456"` → HTTP 200.

At demo time the tower is offline, so no new entry is pushed — receipts stay on-tower and still verify locally against `cosign.pub`.

---

## 3. Cosign public-key fingerprint

```
a4d73120c312d94bdd6cbdfa6f3d629cfff4b85e7addde5f9c3fd4c02341eb30
```

This is `sha256` of the PEM rendered with `\n` line separators and **no trailing newline** — the
exact string the five flagship `/khipu/pubkey` endpoints and `szl-holdings/.github/cosign.pub`
serve. Reproduce it: `printf '%s' "$(cat cosign.pub)" | sha256sum`.

Bundle sha256: `88b99afc581e8c03d13c1033306c08c1027e51189f4f6c9f87223091c1119218`

---

## 4. Safety property — Khipu Consensus BFT 3-of-4

Four flagship organs (a11oy, sentra, amaru, killinchu) each hold an independent ECDSA-P256 cosign
key. An action is **canonical only when ≥ 3 of the 4 organs sign the same `action_hash` over DSSE**.

> With n = 4 witnesses and threshold t = 3, the protocol tolerates f = n − t = **1** Byzantine,
> crashed, or unreachable organ. **3-of-4 ⇒ action CANONICAL. 2-of-4 ⇒ action REJECTED (fail CLOSED).**

Demonstrate live: `./kill_organ.sh sentra` (→ 3-of-4, still canonical) then a second
`./kill_organ.sh amaru` (→ 2-of-4, mission REJECTED). `./restore_organ.sh <organ>` reverses it.

---

## 5. Where to look

- Operator shell (live during demo): <http://localhost:8080>
- Demo + dry-run repo: <https://github.com/szl-holdings/warhacker-demo>
- Signed bundle release: <https://github.com/szl-holdings/uds-bundles/releases/tag/szl-warhacker-uds-v1.0.0>
- Flagship organs: <https://github.com/szl-holdings/a11oy> · `/sentra` · `/amaru` · `/killinchu` · `/rosie` · `/vessels` · `/hatun-mcp`
- Khipu Consensus: <https://github.com/szl-holdings/khipu-consensus>
- Lean proof base (749/14/163): <https://github.com/szl-holdings/lutar-lean>

— Yachay, SZL Holdings
