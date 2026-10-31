"""dm17: derive the datamap record layout from the initializers, record-centric.

dm13 now finds the stores, but dumping whole initializer functions is too
verbose to read.  This script keeps the fast byte prefilter for the stores,
then disassembles only the functions that own a store, with register tracking,
and answers three questions:

  1. what is the stride between consecutive records?   (diff histogram of
     neighbouring name stores inside one function)
  2. where inside a record does each datum live?       (histogram of
     store_dst - name_dst: stride independent, so it works even before the
     stride is known)
  3. what does one record actually contain?            (fully annotated
     dumps of a few records: every store in [name-0x88, name+0x40] with its
     value resolved to an int or a string)

Writes temp/dm17.txt.

usage: python dm17.py [lo-hi]      (hex dst range, default 0x14e600000-0x14e740000)
"""
import bisect
import os
import pickle
import re
import struct
import sys
from collections import Counter, defaultdict

import capstone

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "dm11_cache.pkl")
lo_s = sys.argv[1] if len(sys.argv) > 1 else "0x14e600000-0x14e740000"
dlo, dhi = (int(x, 16) for x in lo_s.split("-"))
WINDOW_BACK, WINDOW_FWD = 0x88, 0x40

lines = []


def p(s=""):
    lines.append(s)


with open(CACHE, "rb") as fh:
    C = pickle.load(fh)
funcs, ident, secs = C["funcs"], C["ident"], C["secs"]
fstarts = [f[0] for f in funcs]
data = open(PATH, "rb").read()


def find(va):
    for s in secs:
        if s[1] <= va < s[1] + max(s[2], s[3]):
            return s, va - s[1]
    return None, None


def rd(va, n):
    s, d = find(va)
    if s is None or d >= s[3]:
        return b"\x00" * n
    return data[s[4] + d:s[4] + d + n]


def func_of(va):
    i = bisect.bisect_right(fstarts, va) - 1
    if i >= 0 and funcs[i][0] <= va < funcs[i][1]:
        return funcs[i]
    return None


ts = next(s for s in secs if s[5] & 0x20)
text = data[ts[4]:ts[4] + ts[3]]
tva = ts[1]

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
md.skipdata = True
X86 = capstone.x86

MODRM = rb"[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]"
PFX = rb"(?:\x66|\xF3|\xF2|\x48|\x49|\x4C|\x4D|)"
STORE_RE = re.compile(
    rb"(?:" + PFX + rb"\x0F(?:\x11|\x7F)|" + PFX + rb"(?:\x88|\x89|\xC6|\xC7))"
    + MODRM)

pre = []
for m in STORE_RE.finditer(text):
    off = m.end()
    if off + 4 > len(text):
        continue
    dst = tva + off + 4 + struct.unpack_from("<i", text, off)[0]
    if dlo <= dst < dhi:
        pre.append(tva + m.start())
p("## dst range %#x..%#x ; prefetched store candidates %d" % (dlo, dhi, len(pre)))

raw_stores, seen = [], set()
md1 = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md1.detail = True
for iva in pre:
    for ins in md1.disasm(text[iva - tva:iva - tva + 16], iva):
        ops = ins.operands
        if ops and ops[0].type == X86.X86_OP_MEM \
                and ops[0].mem.base == X86.X86_REG_RIP:
            dst = ins.address + ins.size + ops[0].mem.disp
            if (ins.address, dst) not in seen:
                seen.add((ins.address, dst))
                raw_stores.append((ins.address, dst, ops[0].size))
        break
p("## confirmed stores in range: %d" % len(raw_stores))

owners = {f for f in (func_of(s[0]) for s in raw_stores) if f}
p("## owning functions: %d" % len(owners))

stores = {}                        # (ins_va, dst) -> [width, value]
dt_leas = []
for f0, f1 in sorted(owners):
    regs = {}
    for ins in md.disasm(rd(f0, f1 - f0), f0):
        if ins.id == 0:
            continue
        mn, ops = ins.mnemonic, ins.operands
        if mn == "lea" and len(ops) == 2 and ops[1].type == X86.X86_OP_MEM \
                and ops[1].mem.base == X86.X86_REG_RIP:
            tgt = ins.address + ins.size + ops[1].mem.disp
            regs[md.reg_name(ops[0].reg)] = ("va", tgt)
            if tgt in ident and ident[tgt].startswith("DT_"):
                dt_leas.append((ins.address, tgt))
        elif mn in ("mov", "movabs") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG:
            if ops[1].type == X86.X86_OP_IMM:
                regs[md.reg_name(ops[0].reg)] = ("imm", ops[1].imm & (2**64 - 1))
            elif ops[1].type == X86.X86_OP_REG:
                regs[md.reg_name(ops[0].reg)] = regs.get(md.reg_name(ops[1].reg))
            else:
                regs[md.reg_name(ops[0].reg)] = None
        elif ops and ops[0].type == X86.X86_OP_REG and len(ops) == 2 \
                and ops[0].reg == ops[1].reg:
            regs[md.reg_name(ops[0].reg)] = ("imm", 0)
        elif ops and ops[0].type == X86.X86_OP_REG:
            regs[md.reg_name(ops[0].reg)] = None
        if ops and ops[0].type == X86.X86_OP_MEM \
                and ops[0].mem.base == X86.X86_REG_RIP:
            dst = ins.address + ins.size + ops[0].mem.disp
            val = None
            if len(ops) == 2:
                if ops[1].type == X86.X86_OP_IMM:
                    val = ops[1].imm & (2**64 - 1)
                elif ops[1].type == X86.X86_OP_REG:
                    got = regs.get(md.reg_name(ops[1].reg))
                    if got:
                        val = got[1]
            stores[(ins.address, dst)] = [ops[0].size, val]
p("## tracked stores %d ; valued %d ; DT_ leas %d"
  % (len(stores), sum(1 for v in stores.values() if v[1] is not None),
     len(dt_leas)))

# ---------------------------------------------------------------------------
# name stores = the anchor of every record
# ---------------------------------------------------------------------------
name_st = []                       # (dst, ins_va, name, func)
for (iva, dst), (_w, val) in stores.items():
    if val is not None and val in ident:
        s = ident[val]
        if s.startswith("m_") or s.startswith("DT_"):
            f = func_of(iva)
            name_st.append((dst, iva, s, f[0] if f else 0))
name_st.sort()
p("## name/class stores: %d (m_* %d, DT_* %d)"
  % (len(name_st), sum(1 for n in name_st if n[2].startswith("m_")),
     sum(1 for n in name_st if n[2].startswith("DT_"))))

by_func = defaultdict(list)
for rec in name_st:
    if rec[2].startswith("m_"):
        by_func[rec[3]].append(rec)

diffs = Counter()
for f, rs in by_func.items():
    for a, b in zip(rs, rs[1:]):
        diffs[b[0] - a[0]] += 1
p("## stride: diff between neighbouring m_* stores in one function")
p("   %s" % " ".join("%#x:%d" % kv for kv in diffs.most_common(10)))

# slot histogram: store_dst - name_dst for stores near the same name
fld_index = defaultdict(list)
for (iva, dst), (w, val) in sorted(stores.items()):
    fld_index[func_of(iva)[0] if func_of(iva) else 0].append((dst, w, val))
slot_hist = Counter()
for f, rs in by_func.items():
    near = fld_index.get(f, ())
    for name_dst, _iva, _nm, _f in rs:
        for dst, w, val in near:
            if -WINDOW_BACK <= dst - name_dst <= WINDOW_FWD:
                slot_hist[dst - name_dst] += 1
p("## slot histogram (store_dst - name_dst)")
for off, n in sorted(slot_hist.items()):
    p("   %+#06x %5d" % (off, n))

# ---------------------------------------------------------------------------
# per-run stride: name stores sorted per function, consecutive diffs
# ---------------------------------------------------------------------------
p()
p("## largest m_* runs per function (dst diffs)")
runs = sorted(((len(rs), f) for f, rs in by_func.items()), reverse=True)[:6]
for n, f in runs:
    rs = by_func[f]
    p("### func %#x  %d name stores  %#x..%#x" % (f, n, rs[0][0], rs[-1][0]))
    ds = [b[0] - a[0] for a, b in zip(rs, rs[1:])]
    p("    diffs %s" % " ".join("%#x" % d for d in ds[:24]))
    p("    hist  %s" % " ".join("%#x:%d" % kv
                               for kv in Counter(ds).most_common(6)))


# ---------------------------------------------------------------------------
# record dumps
# ---------------------------------------------------------------------------
def show(val):
    if val is None:
        return "?"
    if val in ident:
        return '"%s"' % ident[val]
    if val < 0x100000:
        return str(val)
    return "%#x" % val


p()
p("## record dumps")
shown = 0
for name_dst, iva, nm, f in name_st:
    if not nm.startswith("m_") or shown >= 14:
        continue
    near = [(d - name_dst, w, v) for d, w, v in fld_index.get(f, ())
            if -WINDOW_BACK <= d - name_dst <= WINDOW_FWD]
    if len(near) < 4:
        continue
    shown += 1
    p("### name %#x %-28s ins %#x func %#x" % (name_dst, nm, iva, f))
    for off, w, v in sorted(near, key=lambda t: t[0]):
        p("    %+#06x  %#010x w=%d %s" % (off, name_dst + off, w, show(v)))

p()
p("## DT_ class-name stores (class headers)")
for dst, iva, nm, f in name_st:
    if nm.startswith("DT_"):
        p("### %#x %s ins %#x func %#x" % (dst, nm, iva, f))
        near = [(d - dst, w, v) for d, w, v in fld_index.get(f, ())
                if -0x100 <= d - dst <= 0x100]
        for off, w, v in sorted(near, key=lambda t: t[0]):
            p("    %+#06x  %#010x w=%d %s" % (off, dst + off, w, show(v)))

with open(os.path.join(HERE, "dm17.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("dm17.txt: %d lines" % len(lines))
