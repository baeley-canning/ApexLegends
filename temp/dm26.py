"""dm26: (1) why do 4050 name slots collapse to ~826 usable records,
(2) what does the 0x68 block *before* a "DT_xxx" name slot hold (datamap_t
header: dataDesc ptr, field count, struct size, base map) -- that header is
what should bound a class's record array, replacing the fragile
"walk back while the name starts with m_" heuristic.

Read-only, uses dm11_cache.pkl.
"""
import os
import pickle
import struct
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
C = pickle.load(open(os.path.join(HERE, "dm11_cache.pkl"), "rb"))
img, ident, slots = C["img"], C["ident"], C["slots"]
out = []


def p(s=""):
    out.append(s)
    print(s)


def g(va):
    return img.get(va)


def raw(va, n):
    b = bytearray()
    for k in range(n):
        v = g(va + k)
        if v is None:
            return None
        b.append(v)
    return bytes(b)


def u32(va):
    b = raw(va, 4)
    return None if b is None else struct.unpack("<I", b)[0]


def i32(va):
    b = raw(va, 4)
    return None if b is None else struct.unpack("<i", b)[0]


def u64(va):
    b = raw(va, 8)
    return None if b is None else struct.unpack("<Q", b)[0]


def u8(va):
    v = g(va)
    return v


SIZES = (0, 1, 2, 4, 8, 12, 16, 24, 32, 64)
p("## slot reject audit (base = name_store - 0x28)")
reasons = Counter()
good = []
for iva, dst, nm, nva in slots:
    b = dst - 0x28
    t, off, sz = i32(b), i32(b + 4), i32(b + 0x0C)
    if t is None or off is None or sz is None:
        reasons["unreadable"] += 1
        continue
    if not (0 <= t <= 24):
        reasons["type out of range (%d)" % t] += 1
        continue
    if not (0 <= off < 0x10000) or off % 4:
        reasons["offset %s" % ("neg/huge" if off < 0 or off >= 0x10000 else "not %%4")] += 1
        continue
    if sz not in SIZES:
        reasons["size %d" % sz] += 1
        continue
    if t == 0 and off == 0 and sz == 0:
        reasons["all-zero frame"] += 1
        continue
    reasons["ok"] += 1
    good.append((b, nm, t, off, sz, iva))
for k, v in reasons.most_common():
    p("     %-24s %5d" % (k, v))

p("")
p("## fields per record frame: distinct names at the same base?")
per_base = Counter(b for b, *_ in good)
p("     bases %d ; max names in one frame %d ; dups %d"
  % (len(per_base), max(per_base.values()),
     sum(1 for v in per_base.values() if v > 1)))

# ---------------------------------------------------------------------------
# datamap_t header hunt: frame that carries the DT_ name, plus the 0x68 blocks
# before it, annotated with every pointer-ish value
# ---------------------------------------------------------------------------
p("")
p("## DT_ name slots and the surrounding frames")
hdr = [(dst - 0x28, nm) for iva, dst, nm, nva in slots if nm.startswith("DT_")]
bases = {b for b, *_ in good}
p("     DT_ frames: %d" % len(hdr))


def ann(v):
    if not v:
        return "0"
    s = []
    for k in range(48):
        c = g(v + k)
        if c is None:
            break
        if c == 0:
            if len(s) >= 3:
                return "'%s'" % bytes(s).decode("latin-1")
            break
        if not (32 <= c < 127):
            break
        s.append(c)
    i = ident.get(v)
    if i:
        return "ident:%s" % i
    if 0x140000000 <= v < 0x150000000:
        return "@%#x%s" % (v, " (record base)" if v in bases else "")
    return "%#x" % v


for b, nm in sorted(hdr, key=lambda x: x[1]):
    p("")
    p("=== %s  name frame %#x" % (nm, b))
    for f in range(-2, 2):
        fb = b + f * 0x68
        cells = []
        for off in (0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C,
                    0x20, 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60):
            q = u64(fb + off)
            if q:
                cells.append("+%02x=%s" % (off, ann(q)))
        p("   [%+d] %#x  %s" % (f, fb, "  ".join(cells) if cells else "(empty)"))

with open(os.path.join(HERE, "dm26.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
