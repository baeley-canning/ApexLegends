"""dm25: dump one datamap record in full, pointer-annotated, to settle what the
unused 8-byte slots (+0x20, +0x50, +0x60) point at -- in particular whether
+0x60 is the *parent/base* datamap (inheritance) the way Source's
typedescription_t / datamap_t chain works, and whether +0x20 is the
pSaveRestoreOps / type-helper.

Read-only: uses the cached rebuilt image from dm11_cache.pkl.
"""
import os
import pickle
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
C = pickle.load(open(os.path.join(HERE, "dm11_cache.pkl"), "rb"))
img, ident, slots = C["img"], C["ident"], C["slots"]


def g(va):
    return img.get(va) or 0


def raw(va, n):
    return bytes(g(va + k) for k in range(n))


def u32(va):
    return struct.unpack("<I", raw(va, 4))[0]


def i32(va):
    return struct.unpack("<i", raw(va, 4))[0]


def u64(va):
    return struct.unpack("<Q", raw(va, 8))[0]


def s_at(va):
    t = bytearray()
    for k in range(64):
        c = g(va + k)
        if c == 0:
            break
        if not (32 <= c < 127):
            return None
        t.append(c)
    return t.decode() if len(t) >= 3 else None


def ann_ptr(v):
    if v == 0:
        return "NULL"
    nm = s_at(v)
    if nm:
        return "'%s'" % nm
    if v in ident:
        return "ident:%s" % ident[v]
    # does it look like an address of a record base we have?
    return "%#x" % v


# locate every DT_ record (its +0x28 slot holds the class name)
dt_recs = {}
for iva, dst, nm, nva in slots:
    if nm.startswith("DT_"):
        dt_recs[nm] = dst - 0x28
print("DT_ records: %d" % len(dt_recs))

for want in ("DT_BaseEntity", "DT_Player", "DT_LocalPlayerExclusive",
             "DT_HealthKit", "DT_AI_BaseNPC"):
    b = dt_recs.get(want)
    if b is None:
        print("\n%s: not found in slots" % want)
        continue
    print("\n=== %s  base=%#x" % (want, b))
    for off in range(0, 0x68, 8):
        q = u64(b + off)
        lo = u32(b + off)
        hi = u32(b + off + 4)
        note = ""
        if off in (0x20, 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60):
            note = "  -> " + ann_ptr(q)
        print("  +%02x  %016x  lo=%-12d hi=%-12d%s"
              % (off, q, lo if lo < 0x80000000 else lo - 0x100000000,
                 hi if hi < 0x80000000 else hi - 0x100000000, note))

# how many record bases are referenced by any other record's +0x60?
bases = set()
for iva, dst, nm, nva in slots:
    bases.add(dst - 0x28)
print("\nrecord bases: %d" % len(bases))
link = {}
for b in bases:
    p = u64(b + 0x60)
    if p in bases:
        link[b] = p
print("records whose +0x60 points at another record base: %d" % len(link))
print("records whose +0x20 points at another record base: %d"
      % sum(1 for b in bases if u64(b + 0x20) in bases))
print("records whose +0x50 points at another record base: %d"
      % sum(1 for b in bases if u64(b + 0x50) in bases))
