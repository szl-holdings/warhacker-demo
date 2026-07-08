#!/usr/bin/env python3
# receipt_adversarial_test.py — adversarial negative-test suite for the SZL
# signed-receipt chain (the receipts-governance layer that is REAL TODAY).
# =============================================================================
# scripts/rehearse_ci.sh proves the HAPPY path plus ONE tamper class (edit a
# receipt payload). This module widens the adversarial coverage to the distinct
# forgery classes the DSSE / Ed25519 / SHA-256 scheme genuinely detects, so a
# regression in the verifier is caught loudly. It is fully self-contained: it
# mints an EPHEMERAL Ed25519 key (honest: not a persistent identity; discarded
# at exit), emits a signed hash-chained receipt chain with the SAME scheme as
# scripts/core_demo.sh and scripts/rehearse_ci.sh, then confirms that:
#
#   1. the clean chain verifies fully (positive control — the suite is not just
#      always-failing);
#   2. a PAYLOAD edit is rejected (signature no longer covers the bytes);
#   3. a CROSS-RECEIPT SIGNATURE TRANSPLANT is rejected (an Ed25519 signature is
#      bound to its own payload; it cannot be lifted onto another receipt);
#   4. a CHAIN REORDER / SPLICE is rejected (prev_hash links pin the order);
#   5. a FOREIGN-KEY RE-SIGN forgery is rejected (re-signing a tampered payload
#      with the adversary's OWN key fails against the trusted public key, even
#      after the adversary repairs the SHA-256 hash — you must verify against the
#      pinned key, not any key carried in the envelope);
#   6. a payloadType CONFUSION edit is rejected (the type is inside the DSSE
#      Pre-Authentication Encoding, so changing it invalidates the signature);
#   7. a TRUNCATION (dropping trailing receipts) is rejected WHEN the verifier is
#      given the pinned expected chain head — demonstrating why the head must be
#      anchored out-of-band to detect a shortened-but-internally-consistent chain.
#
# Honest scope: this is the receipts governance layer only — CPU-only, no cluster
# boot, no five-modules-together claim. Same honesty boundary as `make rehearse`.
# It proves tamper-EVIDENCE (edits are detected), never "tamper-proof".
#
# Author: SZL Holdings Platform Team · Apache-2.0
import base64
import copy
import hashlib
import json
import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.exceptions import InvalidSignature

PT = "application/vnd.szl.receipt.v1+json"


def pae(pt, body):
    """Canonical DSSE Pre-Authentication Encoding (identical to core_demo.sh)."""
    t = pt.encode()
    return b" ".join([b"DSSEv1", str(len(t)).encode(), t, str(len(body)).encode(), body])


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def b64u_decode(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def receipt_hash(rec):
    canon = json.dumps(rec["envelope"], sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()


class VerificationError(Exception):
    """Raised when a receipt chain fails signature, link, or head verification."""


def verify_chain(chain, pub, expected_head=None):
    """Fail-closed verifier: raise VerificationError on the FIRST problem.

    Returns the chain head hash on success. When ``expected_head`` is provided it
    is asserted against the computed head, which is what lets an out-of-band
    anchor detect truncation of an otherwise internally-consistent chain.
    """
    if not chain:
        raise VerificationError("empty chain")
    prev = "GENESIS"
    for i, rec in enumerate(chain):
        env = rec["envelope"]
        body = base64.b64decode(env["payload"])
        try:
            pub.verify(b64u_decode(env["signatures"][0]["sig"]),
                       pae(env["payloadType"], body))
        except InvalidSignature:
            raise VerificationError(f"signature invalid at index {i}")
        if rec["chain"]["prev_hash"] != prev:
            raise VerificationError(f"prev_hash link break at index {i}")
        if rec["chain"]["hash"] != receipt_hash(rec):
            raise VerificationError(f"stored hash mismatch at index {i}")
        prev = rec["chain"]["hash"]
    if expected_head is not None and prev != expected_head:
        raise VerificationError("chain head does not match pinned head")
    return prev


def build_chain(priv):
    """Emit a signed, hash-chained receipt chain (same scheme as core_demo.sh)."""
    events = [
        {"action": "deploy", "workload": "a11oy", "verdict": "admit"},
        {"action": "deploy", "workload": "killinchu", "verdict": "admit"},
        {"action": "mission", "track_id": "4840D6", "verdict": "threat_assess"},
        {"action": "deploy", "workload": "receipts-server", "verdict": "admit"},
    ]
    chain = []
    prev = "GENESIS"
    for ev in events:
        body = json.dumps(ev, sort_keys=True, separators=(",", ":")).encode()
        env = {
            "payloadType": PT,
            "payload": base64.b64encode(body).decode(),
            "signatures": [{"sig": b64u(priv.sign(pae(PT, body)))}],
        }
        rec = {"envelope": env, "chain": {"prev_hash": prev}}
        rec["chain"]["hash"] = receipt_hash(rec)
        chain.append(rec)
        prev = rec["chain"]["hash"]
    return chain


def _set_payload(rec, obj):
    body = json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()
    rec["envelope"]["payload"] = base64.b64encode(body).decode()


PASS = 0
FAIL = 0


def expect_reject(name, chain, pub, expected_head=None):
    """Assert the verifier REJECTS a forged chain (loud on a silent accept)."""
    global PASS, FAIL
    try:
        verify_chain(chain, pub, expected_head=expected_head)
    except VerificationError as e:
        print(f"  OK   rejected: {name} -> {e}")
        PASS += 1
        return
    print(f"  FAIL accepted forgery: {name} (tamper NOT detected)")
    FAIL += 1


def expect_accept(name, chain, pub, expected_head=None):
    global PASS, FAIL
    try:
        head = verify_chain(chain, pub, expected_head=expected_head)
    except VerificationError as e:
        print(f"  FAIL rejected a valid chain: {name} -> {e}")
        FAIL += 1
        return
    print(f"  OK   accepted: {name} (head={head[:16]}...)")
    PASS += 1


def main():
    priv = Ed25519PrivateKey.generate()
    pub = priv.public_key()
    clean = build_chain(priv)
    head = clean[-1]["chain"]["hash"]

    print("SZL receipt-chain adversarial suite (ephemeral Ed25519; discarded at exit)")
    print(f"  built clean chain: {len(clean)} receipts, head={head[:16]}...")
    print("-" * 78)

    # 1. Positive control — the clean chain must verify (with and without head pin).
    expect_accept("clean chain", copy.deepcopy(clean), pub, expected_head=head)

    # 2. Payload edit — flip a verdict.
    c = copy.deepcopy(clean)
    _set_payload(c[1], {"action": "deploy", "workload": "killinchu", "verdict": "deny"})
    expect_reject("payload edit (admit->deny)", c, pub)

    # 3. Cross-receipt signature transplant — lift receipt #0's signature onto #2.
    c = copy.deepcopy(clean)
    c[2]["envelope"]["signatures"][0]["sig"] = clean[0]["envelope"]["signatures"][0]["sig"]
    c[2]["chain"]["hash"] = receipt_hash(c[2])  # adversary repairs the hash
    c[3]["chain"]["prev_hash"] = c[2]["chain"]["hash"]
    c[3]["chain"]["hash"] = receipt_hash(c[3])
    expect_reject("cross-receipt signature transplant", c, pub)

    # 4. Chain reorder / splice — swap receipts #1 and #2.
    c = copy.deepcopy(clean)
    c[1], c[2] = c[2], c[1]
    expect_reject("chain reorder / splice (#1<->#2)", c, pub)

    # 5. Foreign-key re-sign forgery — adversary re-signs a tampered payload with
    #    THEIR own Ed25519 key and repairs the hash chain; must still fail against
    #    the trusted public key.
    c = copy.deepcopy(clean)
    adversary = Ed25519PrivateKey.generate()
    forged = {"action": "deploy", "workload": "killinchu", "verdict": "deny"}
    body = json.dumps(forged, sort_keys=True, separators=(",", ":")).encode()
    c[1]["envelope"]["payload"] = base64.b64encode(body).decode()
    c[1]["envelope"]["signatures"][0]["sig"] = b64u(adversary.sign(pae(PT, body)))
    c[1]["chain"]["hash"] = receipt_hash(c[1])
    c[2]["chain"]["prev_hash"] = c[1]["chain"]["hash"]
    c[2]["chain"]["hash"] = receipt_hash(c[2])
    c[3]["chain"]["prev_hash"] = c[2]["chain"]["hash"]
    c[3]["chain"]["hash"] = receipt_hash(c[3])
    expect_reject("foreign-key re-sign forgery", c, pub)

    # 6. payloadType confusion — the type is inside the DSSE PAE.
    c = copy.deepcopy(clean)
    c[0]["envelope"]["payloadType"] = "application/vnd.szl.receipt.v2+json"
    c[0]["chain"]["hash"] = receipt_hash(c[0])
    c[1]["chain"]["prev_hash"] = c[0]["chain"]["hash"]
    c[1]["chain"]["hash"] = receipt_hash(c[1])
    expect_reject("payloadType confusion", c, pub)

    # 7. Truncation — drop the last receipt. Internally consistent, so it is only
    #    caught when the verifier is anchored to the pinned expected head.
    c = copy.deepcopy(clean)[:-1]
    expect_accept("truncated chain WITHOUT head pin (internally consistent)", c, pub)
    expect_reject("truncated chain WITH pinned head", c, pub, expected_head=head)

    print("-" * 78)
    print(f"RESULT: {PASS} passed, {FAIL} failed")
    if FAIL:
        print("FAIL -- an adversarial forgery was not detected")
        return 1
    print("PASS -- every forgery class rejected; clean chain verifies")
    return 0


if __name__ == "__main__":
    sys.exit(main())
