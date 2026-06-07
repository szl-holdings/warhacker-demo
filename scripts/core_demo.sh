#!/usr/bin/env bash
# core_demo.sh — SZL signed-receipt-chain + tamper-evident proof (LOCAL, NO CLUSTER).
# =============================================================================
# This is the HEART of the pitch (Replit's recommended core demo). It runs the
# real szl-receipts-server in-image signer (Ed25519, canonical DSSE PAE,
# SHA-256 hash chain) entirely on your laptop — no Kubernetes, no GPU, no GHCR
# pull, no founder secret. It then runs a TAMPER TEST that mutates one receipt
# and shows the chain + signature verification BREAK.
#
# What it proves, honestly:
#   1. A real signed receipt CHAIN — each receipt is Ed25519-signed over the
#      canonical DSSE PAE and links to the previous via prev_hash (SHA-256).
#   2. TAMPER-EVIDENCE — flipping a byte in any receipt breaks BOTH its DSSE
#      signature AND the downstream hash chain. The verifier detects it.
#
# Usage:
#   ./scripts/core_demo.sh
#
# Requirements: python3 with the `cryptography` package, and openssl (for the
# Ed25519 keygen). No Docker, no cluster. The same server.py runs in the OCI
# image in production; here we run it as a plain process so judges can see it.
#
# Author: SZL Holdings Platform Team · Apache-2.0
set -euo pipefail

# ---------------------------------------------------------------------------
# Locate the receipts server source. It lives in the szl-uds-deployment repo
# (services/szl-receipts-server/server.py). Allow an override for CI layouts.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PY="${SERVER_PY:-}"
if [ -z "$SERVER_PY" ]; then
  for cand in \
    "$HERE/../../szl-uds-deployment/services/szl-receipts-server/server.py" \
    "$HERE/../szl-uds-deployment/services/szl-receipts-server/server.py" \
    "/home/user/workspace/szl-uds-deployment/services/szl-receipts-server/server.py" \
    "$HERE/server.py"; do
    [ -f "$cand" ] && SERVER_PY="$cand" && break
  done
fi
[ -n "$SERVER_PY" ] && [ -f "$SERVER_PY" ] || {
  echo "FAIL: could not find szl-receipts-server/server.py."
  echo "      Set SERVER_PY=/path/to/server.py and re-run."
  exit 1
}

PORT="${PORT:-8137}"
WORK="$(mktemp -d)"
STORE="$WORK/store"; mkdir -p "$STORE"
KEY="$WORK/ed25519.pem"
trap 'kill ${SRV_PID:-0} 2>/dev/null || true; rm -rf "$WORK"' EXIT

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_hdr="\033[36m"; c_off="\033[0m"
say()  { printf "${c_hdr}==>${c_off} %s\n" "$*"; }
ok()   { printf "  ${c_ok}OK${c_off}   %s\n" "$*"; }
warn() { printf "  ${c_warn}WARN${c_off} %s\n" "$*"; }
die()  { printf "  ${c_err}FAIL${c_off} %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Generate the in-image Ed25519 signing key (what the server uses today).
# ---------------------------------------------------------------------------
say "1/5  Generate Ed25519 signing key (in-image signer; no founder secret)"
openssl genpkey -algorithm ed25519 -out "$KEY" 2>/dev/null \
  && ok "Ed25519 private key generated at \$KEY" \
  || die "openssl could not generate an Ed25519 key"

# ---------------------------------------------------------------------------
# 2. Boot the receipts server (real server.py — same code as the OCI image).
# ---------------------------------------------------------------------------
say "2/5  Boot szl-receipts-server (port $PORT)"
SZL_PORT="$PORT" SZL_RECEIPT_STORE="$STORE" SZL_ED25519_KEY_PATH="$KEY" \
  python3 "$SERVER_PY" > "$WORK/server.log" 2>&1 &
SRV_PID=$!
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.3
done
curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 \
  && ok "server healthy (signed=$(grep -q 'signed=True' "$WORK/server.log" && echo True || echo False))" \
  || { cat "$WORK/server.log"; die "server did not become healthy"; }

# ---------------------------------------------------------------------------
# 3. Build a signed receipt CHAIN (post a few governance events).
# ---------------------------------------------------------------------------
say "3/5  Emit a signed receipt chain (4 governance events)"
for ev in \
  '{"action":"deploy","workload":"a11oy","verdict":"admit"}' \
  '{"action":"deploy","workload":"killinchu","verdict":"admit"}' \
  '{"action":"mission","track_id":"4840D6","verdict":"threat_assess"}' \
  '{"action":"deploy","workload":"rosie","verdict":"admit"}'; do
  curl -fsS -X POST "http://127.0.0.1:$PORT/receipt" -d "$ev" >/dev/null
done
curl -fsS "http://127.0.0.1:$PORT/receipts" > "$WORK/chain.json"
N=$(python3 -c "import json;print(len(json.load(open('$WORK/chain.json'))))")
ok "$N receipts emitted; chain saved to \$WORK/chain.json"

# ---------------------------------------------------------------------------
# 4. VERIFY the chain (signatures + hash links) using a standalone verifier.
#    This re-implements the DSSE PAE + Ed25519 verify + chain-link check so the
#    proof does not depend on the server trusting itself.
# ---------------------------------------------------------------------------
say "4/5  Verify chain: Ed25519 signatures + SHA-256 prev_hash links"
python3 - "$WORK/chain.json" "$KEY" <<'PY'
import sys, json, base64, hashlib
from cryptography.hazmat.primitives.serialization import load_pem_private_key

chain = json.load(open(sys.argv[1]))
priv  = load_pem_private_key(open(sys.argv[2],'rb').read(), password=None)
pub   = priv.public_key()
PT    = "application/vnd.szl.receipt.v1+json"

def pae(pt, body):
    t = pt.encode()
    return b" ".join([b"DSSEv1", str(len(t)).encode(), t, str(len(body)).encode(), body])

def b64u_decode(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def receipt_hash(rec):
    canon = json.dumps(rec["envelope"], sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()

prev = "GENESIS"; sig_ok = 0; link_ok = 0
for i, rec in enumerate(chain):
    env = rec["envelope"]
    body = base64.b64decode(env["payload"])
    raw_sig = b64u_decode(env["signatures"][0]["sig"])
    pub.verify(raw_sig, pae(env.get("payloadType", PT), body))   # raises on bad sig
    sig_ok += 1
    assert rec["chain"]["prev_hash"] == prev, f"link break at {i}: prev mismatch"
    h = receipt_hash(rec)
    assert rec["chain"]["hash"] == h, f"hash mismatch at {i}"
    link_ok += 1
    prev = h

print(f"  signatures verified : {sig_ok}/{len(chain)}")
print(f"  chain links verified: {link_ok}/{len(chain)} (head={prev[:16]}...)")
print("  CHAIN VALID: every receipt is Ed25519-signed and correctly linked.")
PY
ok "chain verified — real signed-receipt-chain"

# ---------------------------------------------------------------------------
# 5. TAMPER TEST — mutate one receipt; show signature AND chain break.
# ---------------------------------------------------------------------------
say "5/5  Tamper test: flip a byte in receipt #2 and re-verify"
python3 - "$WORK/chain.json" "$KEY" <<'PY'
import sys, json, base64, hashlib
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.exceptions import InvalidSignature

chain = json.load(open(sys.argv[1]))
priv  = load_pem_private_key(open(sys.argv[2],'rb').read(), password=None)
pub   = priv.public_key()
PT    = "application/vnd.szl.receipt.v1+json"

def pae(pt, body):
    t = pt.encode()
    return b" ".join([b"DSSEv1", str(len(t)).encode(), t, str(len(body)).encode(), body])
def b64u_decode(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
def receipt_hash(rec):
    canon = json.dumps(rec["envelope"], sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()

# Adversary edits the payload of receipt index 1 (e.g. flips a verdict).
victim = chain[1]
orig_payload = base64.b64decode(victim["envelope"]["payload"]).decode()
tampered = orig_payload.replace("admit", "deny") if "admit" in orig_payload else orig_payload + " "
victim["envelope"]["payload"] = base64.b64encode(tampered.encode()).decode()
print(f"  adversary changed receipt #1 payload:")
print(f"    before: {orig_payload}")
print(f"    after : {tampered}")

# (a) DSSE signature no longer verifies over the tampered payload.
sig_broken = False
env = victim["envelope"]
body = base64.b64decode(env["payload"])
raw_sig = b64u_decode(env["signatures"][0]["sig"])
try:
    pub.verify(raw_sig, pae(env.get("payloadType", PT), body))
    print("  [UNEXPECTED] signature still verified — tamper NOT detected")
except InvalidSignature:
    sig_broken = True
    print("  DETECTED: Ed25519 signature on receipt #1 FAILS (InvalidSignature).")

# (b) The stored chain.hash for the tampered receipt no longer matches, and
#     every downstream receipt's prev_hash now dangles.
new_hash = receipt_hash(victim)
stored_hash = victim["chain"]["hash"]
chain_broken = new_hash != stored_hash
print(f"  recomputed hash of #1: {new_hash[:16]}...")
print(f"  stored   hash of #1  : {stored_hash[:16]}...")
if chain_broken:
    print("  DETECTED: receipt #1 hash changed -> downstream prev_hash links are now broken.")
    # show the dangling link
    if len(chain) > 2:
        print(f"    receipt #2 expects prev_hash={chain[2]['chain']['prev_hash'][:16]}...,"
              f" but #1 now hashes to {new_hash[:16]}... -> MISMATCH")

assert sig_broken and chain_broken, "tamper was NOT detected — demo would be invalid"
print("  TAMPER-EVIDENT: both the signature and the hash chain detect the edit.")
PY
ok "tamper test passed — the edit broke the signature AND the chain"

echo
printf "${c_ok}========================================================${c_off}\n"
printf "${c_ok} CORE DEMO PASSED${c_off}\n"
printf "  Real Ed25519 signed-receipt-chain + tamper-evident proof.\n"
printf "  Ran locally with the in-image signer \u2014 no cluster, no founder secret.\n"
printf "${c_ok}========================================================${c_off}\n"
