"""dm19: what is at a VA?  prints section, raw bytes, ascii and, if the VA
looks like a pointer table, the strings its entries point at.

usage: python dm19.py 0x14220e150 0x141e0b510 ...
"""
import os
import pickle
import sys

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "dm11_cache.pkl")

with open(CACHE, "rb") as fh:
    C = pickle.load(fh)
ident, secs = C["ident"], C["secs"]
data = open(PATH, "rb").read()


def find(va):
    for s in secs:
        if s[1] <= va < s[1] + max(s[2], s[3]):
            return s, va - s[1]
    return None, None


def rd(va, n):
    s, d = find(va)
    if s is None or d >= s[3]:
        return None
    return data[s[4] + d:s[4] + d + n]


for a in sys.argv[1:]:
    va = int(a, 16)
    s, d = find(va)
    buf = rd(va, 0x60)
    print("=== %#x  %s" % (va, "<unmapped>" if s is None else
                           "%s+%#x" % (s[0], d)))
    if buf is None:
        continue
    print("   raw  %s" % " ".join("%02x" % b for b in buf[:32]))
    print("   asc  %s" % "".join(chr(b) if 32 <= b < 127 else "."
                                  for b in buf[:32]))
    for off in range(0, len(buf) - 7, 8):
        q = int.from_bytes(buf[off:off + 8], "little")
        note = ""
        if 0x140000000 <= q < 0x140000000 + 0x10000000:
            s2, d2 = find(q)
            if s2 is not None:
                note = " %s+%#x" % (s2[0], d2)
                if s2[0] in (".rdata", "_RDATA"):
                    b2 = rd(q, 96)
                    t = b2.split(b"\x00")[0] if b2 else b""
                    if t and all(32 <= c < 127 for c in t):
                        note += ' "%s"' % t.decode()
        print("   +%03x %#018x%s" % (off, q, note))
