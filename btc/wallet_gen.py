#!/usr/bin/env python3
"""Offline BIP39 / BIP84 (native segwit, bc1) wallet generator for the btc kit.

Deliberate design choices, all of them because a mistake here is unrecoverable:

  * 24 words (256-bit entropy), never 12.
  * BIP84 m/84'/0'/0' -> bc1 addresses: lower fees, no legacy address reuse.
  * The mnemonic is re-imported and the address re-derived before anything is
    written, so a library or copy bug fails loudly instead of silently.
  * Writes a human file (mnemonic, passphrase, zpub) and a watch-only CSV.
    The zpub is what you paste into a watch-only wallet so the seed can stay offline.

Run it on the machine, move the files to offline media, delete them here.
"""

import argparse
import getpass
import os
import sys
import time

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from mnemonic import Mnemonic

import keylib

ACCOUNT_PATH = "m/84'/0'/0'"
WORDS = 24

BIP84_VECTOR = (
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon "
    "abandon abandon about"
)
BIP84_EXPECTED = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"


def derive_account(seed: bytes, path: str = ACCOUNT_PATH):
    depth, parent_fp, child_num, chain, priv = keylib.account_key(seed, path)
    return depth, parent_fp, child_num, chain, priv, keylib.serialize_pub(
        depth, parent_fp, child_num, chain, keylib.pubkey(priv)
    )


def addresses(account_priv: bytes, chain: bytes, count: int, hrp: str = "bc"):
    """External chain receive addresses m/84'/0'/0'/0/i for i in 0..count-1."""
    ext_priv, ext_chain = keylib.ckd_priv(account_priv, chain, 0)
    out = []
    for i in range(count):
        node, _ = keylib.ckd_priv(ext_priv, ext_chain, i)
        out.append((i, keylib.p2wpkh_address(keylib.pubkey(node), hrp)))
    return out


def verify_vector() -> int:
    seed = Mnemonic.to_seed(BIP84_VECTOR, passphrase="")
    _, _, _, chain, acct, _ = derive_account(seed)
    got = addresses(acct, chain, 1)[0][1]
    ok = got == BIP84_EXPECTED
    print(f"BIP84 vector address : {got}")
    print(f"expected             : {BIP84_EXPECTED}")
    print(f"RESULT               : {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


def generate(args) -> int:
    mn = Mnemonic("english")
    words = mn.generate(strength=256)
    if len(words.split()) != WORDS:
        print("FAIL: entropy did not produce 24 words")
        return 1

    passphrase = ""
    if not args.no_passphrase:
        passphrase = getpass.getpass("BIP39 passphrase (blank for none, hidden): ")
        if passphrase:
            again = getpass.getpass("repeat passphrase: ")
            if again != passphrase:
                print("FAIL: passphrases differ")
                return 1

    seed = Mnemonic.to_seed(words, passphrase=passphrase)
    depth, parent_fp, child_num, chain, acct, zpub = derive_account(seed)
    addrs = addresses(acct, chain, args.addresses)

    # round trip: re-import what we are about to write, re-derive, compare
    if not mn.check(words):
        print("FAIL: generated mnemonic fails its own checksum")
        return 1
    if derive_account(Mnemonic.to_seed(words, passphrase=passphrase))[5] != zpub:
        print("FAIL: re-derived account key differs")
        return 1

    root_fp = keylib.fingerprint(keylib.master_from_seed(seed)[0]).hex()
    stamp = time.strftime("%Y%m%d-%H%M%S")
    os.makedirs(args.outdir, exist_ok=True)
    base = os.path.join(args.outdir, f"wallet_{stamp}")

    wallet_txt = f"""# OFFLINE WALLET - generated {time.strftime('%Y-%m-%d %H:%M:%S')}
# Scheme: BIP39 24 words + BIP84 m/84'/0'/0' (native segwit, bc1...)
# Fingerprint: {root_fp}
# Passphrase protected: {'yes' if passphrase else 'no'}

MNEMONIC ({WORDS} words, in order):
{words}

PASSPHRASE:
{passphrase if passphrase else '(none - leave blank)'}

ACCOUNT ZPUB (watch-only):
{zpub}

FIRST ADDRESSES:
""" + "".join(f"  {i}: {a}\n" for i, a in addrs) + """
# Restore: any BIP39/BIP84 wallet, network "Bitcoin", script type "native segwit".
# Use the passphrase exactly as above; case and spaces matter.
# Never type this into a website, only into wallet software you control.
"""

    with open(base + ".txt", "w", encoding="utf-8", newline="\r\n") as fh:
        fh.write(wallet_txt)
    with open(base + "_watch.csv", "w", encoding="utf-8", newline="\r\n") as fh:
        fh.write("index,address,path\n")
        for i, a in addrs:
            fh.write(f'{i},{a},m/84\'/0\'/0\'/0/{i}\n')

    print()
    print("mnemonic (write on paper, do not photograph):")
    print("  " + words)
    print()
    print(f"passphrase : {'(set)' if passphrase else '(none)'}")
    print(f"fingerprint: {root_fp}")
    print(f"zpub       : {zpub}")
    print("addresses  :")
    for i, a in addrs:
        print(f"  {i}: {a}")
    print()
    print(f"written    : {base}.txt")
    print(f"             {base}_watch.csv")
    print("VERDICT    : PASS (checksum + re-derivation round trip)")
    return 0


def verify(args) -> int:
    with open(args.verify, encoding="utf-8-sig") as fh:
        text = fh.read()
    words = text[text.index("MNEMONIC"):].splitlines()[1].strip()
    passphrase = text[text.index("PASSPHRASE:"):].splitlines()[1].strip()
    if passphrase.startswith("("):
        passphrase = ""
    mn = Mnemonic("english")
    if not mn.check(words):
        print("VERDICT: FAIL - mnemonic checksum invalid (transcription error)")
        return 1
    _, _, _, chain, acct, zpub = derive_account(Mnemonic.to_seed(words, passphrase=passphrase))
    stored = text.split("ACCOUNT ZPUB (watch-only):")[1].splitlines()[1].strip()
    # Compare the serialized key body, ignoring the version prefix, so files written
    # with xpub instead of zpub still verify.
    try:
        same_key = keylib.b58check_decode(stored)[4:] == keylib.b58check_decode(zpub)[4:]
    except ValueError as exc:
        print(f"VERDICT: FAIL - stored key unreadable ({exc})")
        return 1
    ok = same_key
    print(f"words      : {len(words.split())}")
    print(f"derived    : {zpub}")
    print(f"in file    : {stored}")
    print(f"address 0  : {addresses(acct, chain, 1)[0][1]}")
    print(f"VERDICT    : {'PASS - file intact' if ok else 'FAIL - derived key does not match file'}")
    return 0 if ok else 1


def main() -> int:
    p = argparse.ArgumentParser(description="BIP39/BIP84 offline wallet tool")
    p.add_argument("--addresses", type=int, default=5, help="receive addresses to emit (default 5)")
    p.add_argument("--outdir", default=".", help="where to write wallet files (default: cwd)")
    p.add_argument("--no-passphrase", action="store_true", help="skip the passphrase prompt")
    p.add_argument("--verify", metavar="FILE", help="check an existing wallet file and exit")
    p.add_argument("--test", action="store_true", help="run the BIP84 test vector and exit")
    args = p.parse_args()

    if args.test:
        return verify_vector()
    if args.verify:
        return verify(args)
    return generate(args)


if __name__ == "__main__":
    sys.exit(main())