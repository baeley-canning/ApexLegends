import hashlib

print("ripemd160 available:", "ripemd160" in hashlib.algorithms_available)
for mod in ("mnemonic", "ecdsa", "coincurve", "bip_utils"):
    try:
        m = __import__(mod)
        print(mod, "OK", getattr(m, "__file__", ""))
    except Exception as e:
        print(mod, "MISSING", type(e).__name__, e)

from mnemonic import Mnemonic

mn = Mnemonic("english")
print("wordlist size:", len(mn.wordlist))
