#!/usr/bin/env bash
# rehearse_ci.sh — HERMETIC CI variant of `make rehearse`.
# =============================================================================
# `make rehearse` (scripts/rehearse.sh -> core_demo.sh) boots the real
# szl-receipts-server, whose server.py lives in the SIBLING repo
# szl-uds-deployment. That sibling is not checked out in CI, so the full
# rehearsal cannot run hermetically here.
#
# This target runs the SAME receipts-governance proof — the part that is REAL
# AND RUNNING TODAY — fully self-contained, so it runs in CI with no sibling
# repo, no cluster, no GPU, and no committed secret:
#
#   * generates an EPHEMERAL Ed25519 signing key (honest: not a persistent
#     identity; logged as ephemeral),
#   * emits a hash-chained, Ed25519-signed DSSE receipt chain over the
#     canonical DSSE Pre-Authentication Encoding (identical scheme + PAE +
#     SHA-256 chain as scripts/core_demo.sh),
#   * verifies every signature and every prev_hash link OFFLINE with the public
#     key only,
#   * runs the always-on single-byte TAMPER negative test and proves the edit
#     breaks BOTH the signature AND the hash chain (loud failure if it does
#     not — never a silent pass),
#   * writes the signed receipt chain + public key + a PROOF.txt to
#     $ARTIFACT_DIR so CI can upload them as a workflow artifact.
#
# Honest scope: receipts governance layer only — CPU-only, no cluster boot, no
# five-modules-together claim. Same honesty boundary as `make rehearse`.
#
# Author: SZL Holdings Platform Team · Apache-2.0
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT/artifacts}"
mkdir -p "$ARTIFACT_DIR"

c_ok="\033[32m"; c_err="\033[31m"; c_hdr="\033[36m"; c_off="\033[0m"
hdr() { printf "${c_hdr}========================================================${c_off}\n"; }

hdr
printf "${c_hdr} SZL Warhacker rehearsal (CI, hermetic) — receipts verify + tamper rejected${c_off}\n"
hdr
echo

KEY="$(mktemp)"; trap 'rm -f "$KEY"' EXIT
echo "[1/3] Generate EPHEMERAL Ed25519 signing key (honest: not a persistent identity)"
openssl genpkey -algorithm ed25519 -out "$KEY" 2>/dev/null \
  && echo "  OK   ephemeral Ed25519 key generated (discarded at exit)" \
  || { printf "${c_err}  FAIL${c_off} openssl could not generate an Ed25519 key\n"; exit 1; }
echo

echo "[2/3] Emit -> verify -> tamper, self-contained (same scheme as core_demo.sh)"
echo "------------------------------------------------------------------------------"
ARTIFACT_DIR="$ARTIFACT_DIR" python3 - "$KEY" <<'PY'
import sys, os, json, base64, hashlib
from cryptography.hazmat.primitives.serialization import load_pem_private_key, Encoding, PublicFormat
from cryptography.exceptions import InvalidSignature

KEY = sys.argv[1]
ART = os.environ["ARTIFACT_DIR"]
PT  = "application/vnd.szl.receipt.v1+json"

priv = load_pem_private_key(open(KEY, "rb").read(), password=None)
pub  = priv.public_key()

def pae(pt, body):
    t = pt.encode()
    return b" ".join([b"DSSEv1", str(len(t)).encode(), t, str(len(body)).encode(), body])

def b64u(b):  # url-safe, no padding (matches core_demo verify)
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def b64u_decode(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def receipt_hash(rec):
    canon = json.dumps(rec["envelope"], sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()

events = [
    {"action": "deploy",  "workload": "a11oy",           "verdict": "admit"},
    {"action": "deploy",  "workload": "killinchu",        "verdict": "admit"},
    {"action": "mission", "track_id": "4840D6",           "verdict": "threat_assess"},
    {"action": "deploy",  "workload": "receipts-server",  "verdict": "admit"},
]

# ---- emit a signed, hash-chained receipt chain ----------------------------
chain = []
prev = "GENESIS"
for ev in events:
    body = json.dumps(ev, sort_keys=True, separators=(",", ":")).encode()
    payload_b64 = base64.b64encode(body).decode()
    sig = priv.sign(pae(PT, body))
    env = {"payloadType": PT, "payload": payload_b64,
           "signatures": [{"sig": b64u(sig)}]}
    rec = {"envelope": env, "chain": {"prev_hash": prev}}
    rec["chain"]["hash"] = receipt_hash(rec)
    chain.append(rec)
    prev = rec["chain"]["hash"]
print(f"  emitted {len(chain)} signed receipts (Ed25519 over DSSE PAE, SHA-256 chain)")

# ---- verify every signature + chain link OFFLINE --------------------------
prev = "GENESIS"; sig_ok = 0; link_ok = 0
for i, rec in enumerate(chain):
    env = rec["envelope"]
    body = base64.b64decode(env["payload"])
    pub.verify(b64u_decode(env["signatures"][0]["sig"]), pae(env["payloadType"], body))
    sig_ok += 1
    assert rec["chain"]["prev_hash"] == prev, f"link break at {i}"
    assert rec["chain"]["hash"] == receipt_hash(rec), f"hash mismatch at {i}"
    link_ok += 1
    prev = rec["chain"]["hash"]
print(f"  verified signatures : {sig_ok}/{len(chain)}")
print(f"  verified chain links: {link_ok}/{len(chain)} (head={prev[:16]}...)")
assert sig_ok == link_ok == len(chain), "chain did not fully verify"

# ---- TAMPER negative test (must break BOTH sig and chain) -----------------
victim = json.loads(json.dumps(chain[1]))  # deep copy
orig = base64.b64decode(victim["envelope"]["payload"]).decode()
tampered = orig.replace("admit", "deny")
victim["envelope"]["payload"] = base64.b64encode(tampered.encode()).decode()

sig_broken = False
try:
    pub.verify(b64u_decode(victim["envelope"]["signatures"][0]["sig"]),
               pae(victim["envelope"]["payloadType"],
                   base64.b64decode(victim["envelope"]["payload"])))
except InvalidSignature:
    sig_broken = True
chain_broken = receipt_hash(victim) != chain[1]["chain"]["hash"]
print(f"  tamper test: signature_broken={sig_broken} chain_broken={chain_broken}")
assert sig_broken and chain_broken, "TAMPER NOT DETECTED — proof would be invalid"

# ---- write artifacts ------------------------------------------------------
os.makedirs(ART, exist_ok=True)
with open(os.path.join(ART, "receipt-chain.json"), "w") as f:
    json.dump(chain, f, indent=2)
with open(os.path.join(ART, "ephemeral-ed25519.pub"), "wb") as f:
    f.write(pub.public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo))
with open(os.path.join(ART, "PROOF.txt"), "w") as f:
    f.write(
        "SZL Warhacker rehearsal (CI, hermetic)\n"
        "RESULT: PASS -- receipts verify; tamper rejected\n"
        f"receipts: {len(chain)}  signatures_verified: {sig_ok}  chain_links_verified: {link_ok}\n"
        f"chain_head: {prev}\n"
        "scheme: Ed25519 over canonical DSSE PAE + SHA-256 hash chain\n"
        "key: EPHEMERAL (not a persistent identity; discarded after the run)\n"
        "scope: receipts governance layer only (CPU-only; no cluster/GPU)\n"
    )
print(f"  artifacts written to {ART}/ (receipt-chain.json, ephemeral-ed25519.pub, PROOF.txt)")
PY
echo

echo "[3/3] Adversarial suite — distinct forgery classes must all be rejected"
echo "------------------------------------------------------------------------------"
python3 "$HERE/receipt_adversarial_test.py"
echo

hdr
printf "${c_ok}RESULT: PASS -- receipts verify; tamper + forgery classes rejected${c_off}\n"
hdr
