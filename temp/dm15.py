"""dm15: reconcile dm11 (cache) with dm13 (text scan).

Prints the section map, then a histogram of the store-destination addresses
that dm11 actually captured, so we can see whether the two 0x14E6xxxxx
record addresses can possibly be store targets, and where the real store
targets live.
"""
import os
import pickle
import re
import struct
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "dm15.txt")
lines = []


def p(s=""):
    lines.append(s)
    print(s)


with open(os.path.join(HERE, "dm11_cache.pkl"), "rb") as fh:
    C = pickle.load(fh)

img, slots, secs = C["img"], C["slots"], C["secs"]
base = C["base"]
ident, funcs = C["ident"], C["funcs"]

p("## image base %#x ; sections %d" % (base, len(secs)))
for nm, sva, vs, rs, rp, ch in secs:
    p("   %-10s va %#012x vsize %#010x raw %#010x ch %#010x  end %#012x"
      % (nm, sva, vs, rs, ch, sva + max(vs, rs)))

ks = img.keys()
p("## img bytes: %d ; va range %#x .. %#x"
  % (len(ks), min(ks), max(ks)))

pg = Counter(k >> 20 for k in ks)
p("## img va pages (1MB), top 24: %s"
  % " ".join("%#x:%d" % (k, v) for k, v in pg.most_common(24)))

# every 0x68-aligned anchor in the cache's own numbering
hist = Counter()
for k in ks:
    hist[(k >> 4) & 0xF] += 1
p("## img low-nibble histogram: %s" % dict(sorted(hist.items())))

p("## slots: %d" % len(slots))
spg = Counter(d >> 20 for _i, d, _n, _v in slots)
p("## slot dst pages, top 16: %s"
  % " ".join("%#x:%d" % (k, v) for k, v in spg.most_common(16)))
p("## slots in 0x14e000000-0x14f000000: %d"
  % sum(1 for _i, d, _n, _v in slots if 0x14E000000 <= d < 0x14F000000))
p("## slot dst range: %#x .. %#x"
  % (min(d for _i, d, _n, _v in slots), max(d for _i, d, _n, _v in slots)))

# where do the strong name-slot stores sit relative to the assumed stride?
sl = sorted(set(d for _i, d, _n, _v in slots))
d68 = Counter()
for a, b in zip(sl, sl[1:]):
    if b - a <= 0x400:
        d68[b - a] += 1
p("## gaps between consecutive name slots (<=0x400), top 14: %s"
  % " ".join("%#x:%d" % (k, v) for k, v in d68.most_common(14)))

# the record addresses dm11 derived, and the stride actually observed
anchors = ("m_cellX", "m_iTeamNum", "m_iHealth", "m_impactEffectColorID")
for a in anchors:
    hits = [(i, d, n, v) for i, d, n, v in slots if n == a]
    p("## name slot '%s': %d" % (a, len(hits)))
    for i, d, n, v in hits[:6]:
        p("     ins %#x -> dst %#x  (str @ %#x)" % (i, d, v))

with open(OUT, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
