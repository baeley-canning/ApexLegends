"""dm13: read the record layout off a real initializer, store by store.

dm12 showed the rebuilt .data image is a merge of overlapping/duplicate writes,
so per-record inference from the image alone stays ambiguous.  This script goes
back to the code: it finds every rip-relative *store* whose destination lies in
the schema arrays of interest, groups the stores by owning function (pdata
bounds from the dm11 cache) and prints those functions fully disassembled with

  * `lea` targets resolved to strings (field names / DT_ names),
  * every store tagged with its destination and slot index,
  * a histogram of (dst - base) % 0x68 so the record slots the initializer
    touches are visible at a glance,
  * a histogram of (dst - base) % 0x68 for *string* stores only, which shows
    at which slot the field name lives.

The store scan is a byte-prefilter (opcode + modrm[mod=00,rm=101]) that only
uses capstone to confirm the few hundred candidates inside the region, so it
runs in seconds instead of minutes.

Reads temp/dm11_cache.pkl, writes temp/dm13.txt.

usage: python dm13.py [lo-hi ...]      (hex ranges, default = both anchors)
"""
import bisect
import os
import pickle
import re
import struct
import sys
from collections import Counter

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "dm13.txt")
CACHE = os.path.join(HERE, "dm11_cache.pkl")

RANGES = []
for a in sys.argv[1:]:
    lo, hi = a.split("-")
    RANGES.append((int(lo, 16), int(hi, 16)))
if not RANGES:
    # no explicit ranges: cluster the known name-slot destinations and take the
    # densest clusters, so the scan always targets a real record array
    RANGES = None                       # filled below, after the cache is read
STRIDE = 0x68

buf = []


def p(s=""):
    buf.append(s)


with open(CACHE, "rb") as fh:
    C = pickle.load(fh)
funcs = C["funcs"]
ident = C["ident"]
secs = C["secs"]
fstarts = [f[0] for f in funcs]

if RANGES is None:
    dsts = sorted({d for _i, d, _n, _v in C["slots"]})
    clusters, cur = [], []
    for d in dsts:
        if cur and d - cur[-1] > 0x2000:
            clusters.append(cur)
            cur = []
        cur.append(d)
    if cur:
        clusters.append(cur)
    clusters = [c for c in clusters if len(c) >= 16]
    clusters.sort(key=len, reverse=True)
    RANGES = [(c[0] - 0x40, c[-1] + 0x40) for c in clusters[:4]]

pefile.PE(PATH, fast_load=True)
data = open(PATH, "rb").read()


def find(va):
    for nm, sva, vs, rs, rp, ch in secs:
        if sva <= va < sva + max(vs, rs):
            return (nm, sva, vs, rs, rp, ch), va - sva
    return None, None


def rd(va, n):
    s, d = find(va)
    if s is None or d >= s[3]:
        return b"\x00" * n
    return data[s[4] + d:s[4] + d + n]


ts = next(s for s in secs if s[5] & 0x20)
text = data[ts[4]:ts[4] + ts[3]]
tva = ts[1]
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
X86 = capstone.x86
p("## .text %#x + %#x ; funcs %d ; strings %d" % (tva, ts[3], len(funcs),
                                                   len(ident)))

MODRM = rb"[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]"
PFX = rb"(?:\x66|\xF3|\xF2|\x48|\x49|\x4C|\x4D|)"
# longest alternatives first so the match covers prefix+opcode+modrm
STORE_RE = re.compile(
    rb"(?:" + PFX + rb"\x0F(?:\x11|\x7F)|" + PFX + rb"(?:\x88|\x89|\xC6|\xC7))"
    + MODRM)

cand = []
pages = Counter()
tot = 0
for m in STORE_RE.finditer(text):
    tot += 1
    off = m.end()                                    # first disp32 byte
    if off + 4 > len(text):
        continue
    disp = struct.unpack_from("<i", text, off)[0]
    est = tva + off + 4 + disp                       # rip-relative destination
    pages[est >> 20] += 1
    for lo, hi in RANGES:
        if lo <= est < hi:
            cand.append((tva + m.start(), est))
            break
p("## byte-matched store shapes: %d ; candidates in ranges: %d"
  % (tot, len(cand)))
p("## busiest est dst pages: %s"
  % " ".join("%#x:%d" % (k, v) for k, v in pages.most_common(10)))

sites = []          # (ins_va, dst, width, value, mnemonic)
for iva, est in cand:
    for ins in md.disasm(text[iva - tva:iva - tva + 16], iva):
        ops = ins.operands
        if not ops or ops[0].type != X86.X86_OP_MEM:
            break
        if ops[0].mem.base != X86.X86_REG_RIP:
            break
        dst = ins.address + ins.size + ops[0].mem.disp
        if dst != est:
            break
        val = None
        if len(ops) == 2 and ops[1].type == X86.X86_OP_IMM:
            val = ops[1].imm & 0xFFFFFFFFFFFFFFFF
        sites.append((iva, dst, ops[0].size, val, ins.mnemonic))
        break

sites = sorted(set(sites))
p("## verified rip-relative stores: %d" % len(sites))


def stval(va):
    if va is None:
        return "-"
    s = ident.get(va)
    if s:
        return "%#x %r" % (va, s[:40])
    sec, off = find(va)
    if sec:
        return "%#x <%s+%#x>" % (va, sec[0], off)
    return "%#x" % va


def rhist(vals):
    c = Counter(vals)
    return " ".join("+%#x:%d" % (k, v) for k, v in sorted(c.items()))


for lo, hi in RANGES:
    sub = [s for s in sites if lo <= s[1] < hi]
    p()
    p("#" * 70)
    p("### range %#x .. %#x : %d stores" % (lo, hi, len(sub)))
    if not sub:
        p("### nothing found")
        continue
    b0 = sub[0][1]
    p("### first store dst %#x" % b0)
    p()
    p("## stores (dst order)")
    for iva, dst, w, val, mn in sub:
        p("   %#010x  dst %#010x  +%#05x w=%d  %-6s %s"
          % (iva, dst, (dst - b0) % STRIDE, w, mn, stval(val)))
    p()
    p("## slot histogram (all stores)    : %s" % rhist(
        (d - b0) % STRIDE for _, d, _, _, _ in sub))
    p("## slot histogram (string stores) : %s" % rhist(
        (d - b0) % STRIDE for _, d, w, v, _ in sub
        if v is not None and ident.get(v)))
    p("## stride between consecutive dsts: %s" % rhist(
        d2 - d1 for (_, d1, _, _, _), (_, d2, _, _, _)
        in zip(sub, sub[1:]) if 0 < d2 - d1 <= 0x200))

# ---------------------------------------------------------------------------
# owning functions, fully disassembled
# ---------------------------------------------------------------------------
owners = Counter()
for iva, _, _, _, _ in sites:
    i = bisect.bisect_right(fstarts, iva) - 1
    if i >= 0 and funcs[i][0] <= iva < funcs[i][1]:
        owners[funcs[i]] += 1
p()
p("## owning functions: %d" % len(owners))
for (fs, fe), n in owners.most_common():
    p("     %#010x .. %#010x  (%d stores)" % (fs, fe, n))
DUMMY_MARK = 1

MAX_INS = 700


def dump_fn(fs, fe, lo, hi, b0, label):
    p()
    p("=== function %#x .. %#x   %s" % (fs, fe, label))
    code = rd(fs, fe - fs)
    cnt = 0
    for ins in md.disasm(code, fs):
        cnt += 1
        note = ""
        for op in ins.operands:
            if op.type == X86.X86_OP_MEM and op.mem.base == X86.X86_REG_RIP:
                t = ins.address + ins.size + op.mem.disp
                s = ident.get(t)
                if s:
                    note += "   ; %#x %r" % (t, s[:40])
                elif lo - 0x4000 <= t < hi + 0x4000:
                    note += "   ; %#x" % t
        if ins.operands and ins.operands[0].type == X86.X86_OP_MEM \
                and ins.operands[0].mem.base == X86.X86_REG_RIP:
            d = ins.address + ins.size + ins.operands[0].mem.disp
            if lo <= d < hi:
                note += "   <== STORE %#x (+%#x)" % (d, (d - b0) % STRIDE)
        p("   %#010x  %-8s %s%s" % (ins.address, ins.mnemonic,
                                    ins.op_str, note))
        if cnt >= MAX_INS:
            p("   ... (truncated at %d insns)" % MAX_INS)
            break


for lo, hi in RANGES:
    sub = [s for s in sites if lo <= s[1] < hi]
    if not sub:
        continue
    b0 = sub[0][1]
    own = Counter()
    for iva, _, _, _, _ in sub:
        i = bisect.bisect_right(fstarts, iva) - 1
        if i >= 0 and funcs[i][0] <= iva < funcs[i][1]:
            own[funcs[i]] += 1
    for (fs, fe), n in own.most_common(1):
        dump_fn(fs, fe, lo, hi, b0, "(%d stores in %#x..%#x)" % (n, lo, hi))

with open(OUT, "w", encoding="utf-8") as fh:
    fh.write("\n".join(buf) + "\n")
print("wrote %s, %d lines" % (OUT, len(buf)))
