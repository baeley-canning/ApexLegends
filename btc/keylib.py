"""Bitcoin key material: BIP32 derivation, BIP84 addresses, bech32, base58.

Stdlib + `ecdsa` only (pure Python secp256k1). Deliberately small and auditable:
this file is the part that must be correct, so it is written to be read.
"""

import hashlib
import hmac

from ecdsa import SECP256k1, SigningKey

HARDENED = 0x80000000
# BIP84 account keys are serialized with the "zpub" version so wallets pick native segwit.
ACCOUNT_VERSION = bytes.fromhex("04b24746")


# ---------------------------------------------------------------- hashes
def sha256(b: bytes) -> bytes:
    return hashlib.sha256(b).digest()


def hash160(b: bytes) -> bytes:
    return hashlib.new("ripemd160", sha256(b)).digest()


def double_sha256(b: bytes) -> bytes:
    return sha256(sha256(b))


# ---------------------------------------------------------------- bech32 (BIP173)
CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
GEN = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)


def _polymod(values):
    chk = 1
    for v in values:
        top = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i in range(5):
            chk ^= GEN[i] if ((top >> i) & 1) else 0
    return chk


def _hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def _create_checksum(hrp, data, const):
    values = _hrp_expand(hrp) + data
    polymod = _polymod(values + [0, 0, 0, 0, 0, 0]) ^ const
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]


def _convertbits(data, frombits, tobits, pad=True):
    acc = bits = 0
    ret = []
    maxv = (1 << tobits) - 1
    for value in data:
        if value < 0 or value >> frombits:
            raise ValueError("bech32: bad value")
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad:
        if bits:
            ret.append((acc << (tobits - bits)) & maxv)
    elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
        raise ValueError("bech32: bad padding")
    return ret


def bech32_encode(hrp: str, data: list, const: int = 1) -> str:
    combined = data + _create_checksum(hrp, data, const)
    return hrp + "1" + "".join(CHARSET[d] for d in combined)


def encode_segwit_v0(hrp: str, witprog: bytes) -> str:
    return bech32_encode(hrp, [0] + _convertbits(witprog, 8, 5))


# ---------------------------------------------------------------- base58 (BIP32 xpub)
B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def b58encode(raw: bytes) -> str:
    n = int.from_bytes(raw, "big")
    out = ""
    while n:
        n, r = divmod(n, 58)
        out = B58[r] + out
    pad = len(raw) - len(raw.lstrip(b"\0"))
    return "1" * pad + out


def b58decode(s: str) -> bytes:
    n = 0
    for ch in s:
        n = n * 58 + B58.index(ch)
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    pad = len(s) - len(s.lstrip("1"))
    return b"\0" * pad + raw


def b58check_decode(s: str) -> bytes:
    raw = b58decode(s)
    payload, check = raw[:-4], raw[-4:]
    if double_sha256(payload)[:4] != check:
        raise ValueError("base58: bad checksum")
    return payload


def b58check(payload: bytes) -> str:
    return b58encode(payload + double_sha256(payload)[:4])


# ---------------------------------------------------------------- BIP32
def master_from_seed(seed: bytes):
    digest = hmac.new(b"Bitcoin seed", seed, hashlib.sha512).digest()
    return digest[:32], digest[32:]


def pubkey(priv: bytes) -> bytes:
    return SigningKey.from_string(priv, curve=SECP256k1).verifying_key.to_string("compressed")


def ckd_priv(priv: bytes, chain: bytes, index: int):
    if index >= HARDENED:
        data = b"\x00" + priv + index.to_bytes(4, "big")
    else:
        data = pubkey(priv) + index.to_bytes(4, "big")
    digest = hmac.new(chain, data, hashlib.sha512).digest()
    child = (int.from_bytes(digest[:32], "big") + int.from_bytes(priv, "big")) % SECP256k1.order
    if child == 0:
        raise ValueError("derivation produced zero key")
    return child.to_bytes(32, "big"), digest[32:]


def parse_path(path: str) -> list:
    out = []
    for part in path.strip().split("/"):
        if part in ("m", "M", ""):
            continue
        hard = part.endswith(("'", "h", "H"))
        out.append(int(part.rstrip("'hH")) | HARDENED if hard else int(part))
    return out


def fingerprint(priv: bytes) -> bytes:
    return hash160(pubkey(priv))[:4]


def account_key(seed: bytes, path: str = "m/84'/0'/0'"):
    """Return (depth, parent_fingerprint, child_number, chain_code, private_key, zpub)."""
    priv, chain = master_from_seed(seed)
    depth = 0
    parent_fp = b"\0\0\0\0"
    child_num = 0
    for index in parse_path(path):
        parent_fp = fingerprint(priv)
        priv, chain = ckd_priv(priv, chain, index)
        child_num = index
        depth += 1
    return depth, parent_fp, child_num, chain, priv


def serialize_pub(depth: int, parent_fp: bytes, child_num: int, chain: bytes, pub: bytes) -> str:
    payload = (
        ACCOUNT_VERSION
        + bytes([depth])
        + parent_fp
        + child_num.to_bytes(4, "big")
        + chain
        + pub
    )
    return b58check(payload)


def p2wpkh_address(pub: bytes, hrp: str = "bc") -> str:
    return encode_segwit_v0(hrp, hash160(pub))
