"""dm22: derive the datamap record template from the *shape of the code*, not
from a guessed stride.

Discovery that motivates this script (visible in dm21.txt): every record body is
emitted as

    movups [R+0x00], xmm0      ; xmm0 == 0
    ... six 16-byte stores ... ; zero-fills R+0x00 .. R+0x60
    mov    [R+0x28], rax       ; rax = "m_xxx"  <- field name
    ...
    mov    [R+0x60], rax       ; 8-byte tail (DT_ pointer / 0)

so the *start of a run of 16-byte zero stores* is the record base; that yields
stride and every field offset without assuming anything.

Output
  1. rebuilt image + raw file bytes of a probe window
  2. record-base detection (zero-fill runs), per-function stride diffs,
     name-offset histogram
  3. aggregated template: record offset -> widths / value kinds
  4. record-grid overlay of the probe window
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
PROBE = 0x14e699130
PROBEN = 0x150
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


def sname(va):
    """printable ascii string stored at va, else None"""
    if va is None or va < 0x10000:
        return None
    t = rd(va, 96).split(b"\x00")[0]
    if len(t) >= 3 and all(32 <= c < 127 for c in t):
        try:
            return t.decode()
        except UnicodeDecodeError:
            return None
    return None


def ann(q):
    sn = sname(q)
    if sn:
        return " '%s'" % sn
    if q < 0x100000:
        return " =%d" % q
    s, d = find(q)
    return " %s+%#x" % (s[0], d) if s is not None else ""


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

# ---------------------------------------------------------------------------
# 1. which functions touch the whole schema region
# ---------------------------------------------------------------------------
pre, owners = [], set()
for m in STORE_RE.finditer(text):
    off = m.end()
    if off + 4 > len(text):
        continue
    dst = tva + off + 4 + struct.unpack_from("<i", text, off)[0]
    if dlo <= dst < dhi:
        pre.append(tva + m.start())
        f = func_of(tva + m.start())
        if f:
            owners.add(f)
p("## prefilter hits %d  owners %d" % (len(pre), len(owners)))

# ---------------------------------------------------------------------------
# 2. per-function store scan with register tracking
# ---------------------------------------------------------------------------
stores = {}                      # (iva, dst) -> (w, val, func)


def scan(f0, f1):
    regs = {}
    for ins in md.disasm(rd(f0, f1 - f0), f0):
        if ins.id == 0:
            continue
        mn, ops = ins.mnemonic, ins.operands
        if mn == "lea" and len(ops) == 2 and ops[1].type == X86.X86_OP_MEM \
                and ops[1].mem.base == X86.X86_REG_RIP:
            regs[md.reg_name(ops[0].reg)] = (
                "va", ins.address + ins.size + ops[1].mem.disp)
        elif mn in ("mov", "movabs", "movq", "movd") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG:
            if ops[1].type == X86.X86_OP_IMM:
                regs[md.reg_name(ops[0].reg)] = ("imm", ops[1].imm & (2**64 - 1))
            elif ops[1].type == X86.X86_OP_REG:
                regs[md.reg_name(ops[0].reg)] = regs.get(md.reg_name(ops[1].reg))
            else:
                regs[md.reg_name(ops[0].reg)] = None
        elif mn in ("xor", "sub", "pxor", "xorps", "xorpd") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG and ops[1].type == X86.X86_OP_REG \
                and ops[0].reg == ops[1].reg:
            regs[md.reg_name(ops[0].reg)] = ("zero", 0)
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
            stores[(ins.address, dst)] = (ops[0].size, val, (f0, f1))


for f0, f1 in sorted(owners):
    scan(f0, f1)
p("## stores decoded %d" % len(stores))

allst = sorted((iva, dst, w, val, f)
               for (iva, dst), (w, val, f) in stores.items())
inwin = [t for t in allst if dlo <= t[1] < dhi]
p("## stores in window %d" % len(inwin))

# ---------------------------------------------------------------------------
# 3. rebuilt image (known values win; unknown stores only fill holes)
# ---------------------------------------------------------------------------
img = {}


def put(va, w, val):
    for k in range(w):
        img[va + k] = (val >> (8 * k)) & 0xFF if val is not None else 0


for iva, dst, w, val, f in inwin:
    if val is not None:
        put(dst, w, val)
for iva, dst, w, val, f in inwin:
    if val is None:
        for k in range(w):
            img.setdefault(dst + k, 0)

# ---------------------------------------------------------------------------
# 4. record bases = start of a run of >=4 consecutive 16-byte zero stores
# ---------------------------------------------------------------------------
per_f = defaultdict(list)
for iva, dst, w, val, f in inwin:
    per_f[f].append((iva, dst, w, val))

bases = {}
for f, lst in per_f.items():
    zs = sorted({dst for _i, dst, w, val in lst if w == 16 and val == 0})
    i = 0
    while i < len(zs):
        j = i
        while j + 1 < len(zs) and zs[j + 1] - zs[j] == 0x10:
            j += 1
        if j - i + 1 >= 4:
            bases[zs[i]] = f
        i = j + 1
p("## zero-fill runs -> record bases: %d" % len(bases))

blr = sorted(bases)
p()
p("## per-function base diffs (stride)")
byf = defaultdict(list)
for b in blr:
    byf[bases[b]].append(b)
shown = 0
for f, bs in sorted(byf.items(), key=lambda kv: -len(kv[1])):
    if len(bs) < 3:
        continue
    hist = Counter(y - x for x, y in zip(bs, bs[1:]))
    p("   func %#x bases=%-4d %#x..%#x  %s"
      % (f[0], len(bs), bs[0], bs[-1],
         " ".join("%#x:%d" % kv for kv in hist.most_common(6))))
    shown += 1
    if shown >= 40:
        break

# ---------------------------------------------------------------------------
# 5. name offset inside the record
# ---------------------------------------------------------------------------
p()
p("## name-offset histogram: name_dst - record_base")


def base_of(dst, back=8):
    i = bisect.bisect_right(blr, dst) - 1
    for b in reversed(blr[max(0, i - back):i + 1]):
        if 0 <= dst - b < 0x68:
            return b
    return None


nh = Counter()
nmiss = 0
for iva, dst, w, val, f in inwin:
    if val is None or val not in ident:
        continue
    if not ident[val].startswith("m_"):
        continue
    b = base_of(dst)
    if b is None:
        nmiss += 1
    else:
        nh[dst - b] += 1
p("   %s   (unassigned %d)"
  % (" ".join("%#04x:%d" % kv for kv in nh.most_common(8)), nmiss))

# ---------------------------------------------------------------------------
# 6. aggregated template: record offset -> widths / value kinds
# ---------------------------------------------------------------------------
p()
p("## template aggregated over every store that falls inside a known record")
slot, kind = defaultdict(Counter), defaultdict(Counter)
for iva, dst, w, val, f in inwin:
    b = base_of(dst)
    if b is None:
        continue
    off = dst - b
    slot[off][w] += 1
    if val is None:
        kind[off]["?"] += 1
    elif val == 0:
        kind[off]["0"] += 1
    elif val in ident:
        nm = ident[val]
        kind[off]["str:" + ("m_" if nm.startswith("m_") else
                            ("DT_" if nm.startswith("DT_") else "other"))] += 1
    elif val < 0x1000:
        kind[off]["n=%d" % val] += 1
    else:
        s, d = find(val)
        kind[off]["ptr:" + (s[0] if s else "nowhere")] += 1
for off in sorted(slot):
    p("   +%02x  n=%-5d widths %-20s %s"
      % (off, sum(slot[off].values()),
         " ".join("%d:%d" % kv for kv in sorted(slot[off].items())),
         " ".join("%s:%d" % kv for kv in kind[off].most_common(6))))

# ---------------------------------------------------------------------------
# 7. probe window: raw file bytes vs rebuilt image
# ---------------------------------------------------------------------------
for title, getter in (("raw file bytes", "raw"), ("rebuilt image", "img")):
    p()
    p("### %s  %#x .. %#x  (rows not on the 0x68 grid are marked *RL*)"
      % (title, PROBE, PROBE + PROBEN))
    for a in range(PROBE, PROBE + PROBEN, 8):
        if getter == "raw":
            b = rd(a, 8)
        else:
            b = bytes(img.get(a + k, 0) for k in range(8))
        q = struct.unpack("<Q", b)[0]
        star = "" if a in bases else " "
        mark = ""
        if getter == "img" and not all((a + k) in img for k in range(8)):
            mark = "  (holes)"
        p("   %s%#x  %016x  lo32=%-12d%s%s"
          % (star, a, q, struct.unpack("<I", b[:4])[0], ann(q), mark))

# ---------------------------------------------------------------------------
# 8. record grid overlay
# ---------------------------------------------------------------------------
p()
p("### record grid overlay (base = zero-fill run start, stride 0x68)")
for b in [x for x in blr if PROBE - 0x68 <= x < PROBE + PROBEN]:
    p()
    p("  --- base %#x  (func %#x) ---" % (b, bases[b][0]))
    for off in range(0, 0x68, 8):
        a = b + off
        bb = bytes(img.get(a + k, 0) for k in range(8))
        q = struct.unpack("<Q", bb)[0]
        p("      +%02x %016x  lo32=%-12d%s"
          % (off, q, struct.unpack("<I", bb[:4])[0], ann(q)))

with open(os.path.join(HERE, "dm22.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("dm22.txt: %d lines" % len(lines))
