"""dm18: dump raw bytes of a .data window as qwords/dwords, resolving
pointers into .data/.rdata to strings, so the record template can be read
straight off the image (or shown to be merged/zeroed).

usage: python dm18.py 0x14e699860 0x180 [more va len]...
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


def cstr(va, n=64):
    b = rd(va, n)
    if not b:
        return None
    e = b.find(b"\x00")
    if e <= 0:
        return None
    try:
        return b[:e].decode("ascii")
    except UnicodeDecodeError:
        return None


def desc(val):
    s, _ = find(val)
    if s is None or val < 0x10000:
        return ""
    t = cstr(val)
    if t and len(t) >= 3 and all(32 <= ord(ch) < 127 for ch in t):
        return ' -> "%s" (%s)' % (t, s[0])
    if val in ident:
        return " -> name %s (%s)" % (ident[val], s[0])
    return " (%s+%#x)" % (s[0], val - s[1])


args = sys.argv[1:]
for i in range(0, len(args) - 1, 2):
    va, n = int(args[i], 16), int(args[i + 1], 16)
    buf = rd(va, n)
    print("=== %#x (%d bytes)" % (va, n))
    if buf is None:
        print("   <unmapped>")
        continue
    for off in range(0, len(buf) - 7, 8):
        q = int.from_bytes(buf[off:off + 8], "little")
        d0 = int.from_bytes(buf[off:off + 4], "little", signed=True)
        d1 = int.from_bytes(buf[off + 4:off + 8], "little", signed=True)
        print("  +%03x q=%#018x  i32=%d,%d%s"
              % (off, q, d0, d1, desc(q) if q >= 0x10000 else ""))
