"""dm12: structural analysis of the datamap arrays, straight off dm11's cache.

dm11 resolved 1576 field records (name ptr at record+0x38) but *zero* class
header records, and 832 slots preferred a base at name_store-0x08 instead.
This script answers, from the reconstructed .data image:

  1. global scan: among all `(-1,1)` record starts, how many have a known
     string at +0x38 (field name) vs at +0x08 (class name)?
  2. stride histogram between record starts that own a field name;
  3. raw dumps of three regions (one per hypothesis) so the layout is visible;
  4. per-DT_-slot candidate report: where is the class record really.

Reads temp/dm11_cache.pkl, writes temp/dm12.txt.
"""
import os
import pickle
import struct
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "dm12.txt")
CACHE = os.path.join(HERE, "dm11_cache.pkl")

buf = []


def p(s=""):
    buf.append(s)


with open(CACHE, "rb") as fh:
    C = pickle.load(fh)
img = C["img"]
slots = C["slots"]
funcs = C["funcs"]
base = C["base"]
dt_leas = C["dt_leas"]
ident = C["ident"]
secs = C["secs"]
p("## cache: img bytes %d, slots %d, strings %d, dt_leas %d"
  % (len(img), len(slots), len(ident), len(dt_leas)))


# ---------------------------------------------------------------------------
# image access (mirrors dm11)
# ---------------------------------------------------------------------------
def get(va, n):
    b = bytearray()
    for k in range(n):
        v = img.get(va + k)
        if v is None:
            return None
        b.append(v)
    return bytes(b)


def u32(va):
    b = get(va, 4)
    return None if b is None else struct.unpack("<I", b)[0]


def i32(va):
    b = get(va, 4)
    return None if b is None else struct.unpack("<i", b)[0]


def u64(va):
    b = get(va, 8)
    return None if b is None else struct.unpack("<Q", b)[0]


def name_at(va, off):
    v = u64(va + off) if va is not None else None
    return None if v is None else ident.get(v)


def is_hdr(va):
    return i32(va) == -1 and i32(va + 4) == 1


def fmt(v):
    return "(unknown)" if v is None else "%#x" % v


def dump(lo, hi, title):
    p("")
    p("=== %s" % title)
    p("    range %#x .. %#x" % (lo, hi))
    a = lo
    while a < hi:
        v = u64(a)
        if v is None:
            p("    %#010x  (unknown)" % a)
        else:
            note = ""
            if v in ident:
                note = "  => %r" % ident[v]
            elif (v & 0xFFFFFFFF) == 0xFFFFFFFF and (v >> 32) == 1:
                note = "  <= (-1,1) record start"
            elif v == 0:
                note = "  .."
            p("    %#010x  %016x%s" % (a, v, note))
        a += 8
    p("")


# ---------------------------------------------------------------------------
# 1. global scan of record starts
# ---------------------------------------------------------------------------
starts = []
for va in sorted(img):
    if is_hdr(va):
        starts.append(va)
p("## (-1,1) record starts in image: %d" % len(starts))

by38 = [s for s in starts if name_at(s, 0x38)]
by08 = [s for s in starts if name_at(s, 0x08)]
both = [s for s in starts if name_at(s, 0x38) and name_at(s, 0x08)]
p("##   with string at +0x38 (field name): %d" % len(by38))
p("##   with string at +0x08 (class name?): %d" % len(by08))
p("##   with both: %d" % len(both))

p("")
p("## what sits at +0x08 when a field name is at +0x38 (by38):")
c = Counter()
for s in by38:
    n8 = name_at(s, 0x08)
    c[n8 if n8 is None else ("<DT_ str>" if n8.startswith("DT_") else "<other str>")] += 1
for k, v in c.most_common(15):
    p("     %-42s %5d" % (str(k)[:42], v))

p("")
p("## names found at +0x08 for starts that also own +0x38 (sample):")
dp = Counter(name_at(s, 0x08) for s in both)
for k, v in dp.most_common(10):
    p("     %-42s %5d" % (str(k)[:42], v))

p("")
only08 = [s for s in by08 if not name_at(s, 0x38)]
p("## starts with +0x08 string but no +0x38 string: %d ; DT_ among them: %d"
  % (len(only08), sum(1 for s in only08
                      if (name_at(s, 0x08) or "").startswith("DT_"))))
p("## sample 25:")
for s in only08[:25]:
    p("     %#010x +08=%-34r +38=%s off=%s size=%s"
      % (s, (name_at(s, 0x08) or "")[:34], fmt(name_at(s, 0x38)),
         fmt(u32(s + 0x14)), fmt(u32(s + 0x1c))))

# ---------------------------------------------------------------------------
# 2. stride between field records
# ---------------------------------------------------------------------------
p("")
p("## stride between consecutive field records (by38, sorted):")
sd = Counter(b - a for a, b in zip(by38, by38[1:]) if 0 < b - a <= 0x400)
for k, v in sd.most_common(12):
    p("     %+#6x : %5d" % (k, v))

p("")
dt_in = Counter()
for s in by38:
    n8 = name_at(s, 0x08)
    if n8 and n8.startswith("DT_"):
        dt_in[n8] += 1
p("## field records whose +0x08 is a DT_ name: %d (%d distinct)"
  % (sum(dt_in.values()), len(dt_in)))
for k, v in dt_in.most_common(10):
    p("     %-42s %5d" % (k, v))

# ---------------------------------------------------------------------------
# 3. raw dumps of known regions
# ---------------------------------------------------------------------------
dump(0x14e6b3800, 0x14e6b3a40,
     "DT_Player / m_iHealth array (dm11 base 0x14e6b3888)")
dump(0x14e6a5d80, 0x14e6a5ea0,
     "region dm11 scored base=name_store-0x08 (m_iHealth dt=0x14e6a5e48)")
dump(0x14e6b0d40, 0x14e6b1260,
     "DT_BaseEntity array (m_iTeamNum dm11 base 0x14e6b1218)")

# ---------------------------------------------------------------------------
# 4. DT_ slots: where is the class record?
# ---------------------------------------------------------------------------
dtslots = [s for s in slots if s[2].startswith("DT_")]
p("")
p("## DT_ name slots: %d" % len(dtslots))
CANDS = tuple(range(-0x60, 0x10, 4))
cdist = Counter()
for iva, dst, nm, nva in dtslots:
    hits = []
    for c in CANDS:
        b = dst + c
        if is_hdr(b):
            hits.append((c, b))
    cdist[tuple(c for c, _ in hits)] += 1
    p("")
    p("  slot %#x  %r" % (dst, nm))
    if not hits:
        for d in (-0x10, -0x08, 0x00, 0x08):
            v = u64(dst + d)
            p("     %+#5x %s" % (d, "(unknown)" if v is None else "%016x" % v))
        continue
    for c, b in hits:
        p("     start=%#010x (%+#5x) off=%s size=%s flags=%s"
          % (b, c, fmt(u32(b + 0x14)), fmt(u32(b + 0x1c)), fmt(u32(b + 0x20))))
        p("        +08=%-36r +38=%r" % (name_at(b, 0x08), name_at(b, 0x38)))

p("")
p("## distribution of (-1,1) candidate deltas over DT_ slots:")
for k, v in cdist.most_common(10):
    p("     %-30s %5d" % (str(tuple("%+#x" % x for x in k)), v))

p("")
if dtslots:
    _, dst, nm, _ = dtslots[0]
    dump(dst - 0x60, dst + 0x60, "first DT_ slot %r at %#x" % (nm, dst))

with open(OUT, "w", encoding="utf-8") as fh:
    fh.write("\n".join(buf) + "\n")
print("wrote %s, %d lines" % (OUT, len(buf)))

