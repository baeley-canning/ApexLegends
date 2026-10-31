"""Resolve schema records: (class name, field name) -> field offset / size.

dm9 proved the record layout by reading a whole initializer:

    lea  rax, [rip+"m_iHealth"]        ; field name
    mov  [rec+0x14], 0x330             ; offset (written as u64 -> also zeroes +0x18)
    mov  [rec+0x1c], 4                 ; size   (u64)
    mov  [rec+0x38], rax               ; name pointer

i.e. each 0x68-byte record is

    +0x00 i32  -1          +0x04 i32  1
    +0x08 ptr  type descriptor (or 0)
    +0x10 u32  ?           +0x14 u32  field offset
    +0x18 u32  0           +0x1c u32  field size
    +0x20 u32  flags       +0x30 ptr  extra
    +0x38 ptr  "m_xxx" field name  (or "DT_xxx" for the array's own header)

verified on DT_ShieldProp (m_impactEffectColorID 0x1650/1, m_iHealth 0x330/4).

dm10:
  * rebuilds the .data image from the initializer stores (same as dm8),
  * uses the PE exception directory (.pdata) for exact function bounds,
  * attaches to every record the "DT_*" string lea'd by the function that
    initializes it  -> owning class of the record array,
  * scores several candidate layouts per name slot so the layout choice is
    data-driven instead of assumed,
  * chains records with the 0x68 stride into arrays and dumps them.

Output: temp/dm10.txt, temp/dm10_fields.tsv
"""
import bisect
import os
import re
import struct
from collections import Counter, defaultdict

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
PROG = os.path.join(HERE, "dm10_prog.txt")
out = []
open(PROG, "w", encoding="utf-8").close()


def p(s=""):
    out.append(s)
    with open(PROG, "a", encoding="utf-8") as fh:
        fh.write(s + "\n")


def prog(msg):
    with open(PROG, "a", encoding="utf-8") as fh:
        fh.write(msg + "\n")


pe = pefile.PE(PATH, fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase
secs = []
for s in pe.sections:
    secs.append((s.Name.rstrip(b"\x00").decode("latin1"),
                 base + s.VirtualAddress, s.Misc_VirtualSize,
                 s.SizeOfRawData, s.PointerToRawData, s.Characteristics))
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


def cstr(va, n=96):
    b = rd(va, n)
    z = b.find(b"\x00")
    return None if z <= 0 else b[:z].decode("latin1", "replace")


# ---------------------------------------------------------------------------
# strings
# ---------------------------------------------------------------------------
ident = {}                      # va -> ascii string
pat = re.compile(rb"[\x20-\x7e]{3,96}")
for nm, sva, vs, rs, rp, ch in secs:
    if ch & 0x20 or rs > 0x800000:
        continue
    blob = data[rp:rp + rs]
    for m in pat.finditer(blob):
        e = m.end()
        if e < rs and blob[e] == 0 and m.group()[:1].isalpha():
            ident[sva + m.start()] = m.group().decode("latin1")
name_at = {k: v for k, v in ident.items() if v.startswith("m_")}
dt_at = {k: v for k, v in ident.items() if v.startswith("DT_")}
p("## strings: %d field names, %d DT_ names" % (len(name_at), len(dt_at)))

# ---------------------------------------------------------------------------
# function bounds from the exception directory (.pdata)
# ---------------------------------------------------------------------------
def read_pdata():
    dd = pe.OPTIONAL_HEADER.DATA_DIRECTORY[3]
    rva, size = dd.VirtualAddress, dd.Size
    if not rva or size < 12:
        return []
    blob = rd(base + rva, size)
    res = []
    for i in range(0, len(blob) - 11, 12):
        b, e, _u = struct.unpack_from("<III", blob, i)
        if b and e > b:
            res.append((base + b, base + e))
    res.sort()
    return res


funcs = read_pdata()
fstarts = [f[0] for f in funcs]
p("## pdata functions: %d (%#x..%#x)" % (len(funcs),
                                          funcs[0][0] if funcs else 0,
                                          funcs[-1][1] if funcs else 0))


def func_of(va):
    i = bisect.bisect_right(fstarts, va) - 1
    if i >= 0 and funcs[i][0] <= va < funcs[i][1]:
        return funcs[i]
    return None


# ---------------------------------------------------------------------------
# find lea sites onto field names, then simulate the initializers
# ---------------------------------------------------------------------------
ts = next(s for s in secs if s[5] & 0x20)
text = data[ts[4]:ts[4] + ts[3]]
tva = ts[1]

sites = []
leapat = re.compile(rb"[\x48\x4c\x49\x4d]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]")
for m in leapat.finditer(text):
    i = m.start()
    d = struct.unpack_from("<i", text, i + 3)[0]
    tgt = tva + i + 7 + d
    if tgt in name_at:
        sites.append((tva + i, tgt))
p("## lea sites: %d over %d names" % (len(sites), len({t for _, t in sites})))

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
md.skipdata = True
X86 = capstone.x86

stores = {}          # (ins_va, dst) -> (width, value|None)
dt_leas = []         # (ins_va, dt_va)
WINDOW_BACK, WINDOW_FWD = 0x300, 0x500


def reg_of(op):
    return md.reg_name(op.reg) if op.type == X86.X86_OP_REG else None


prog("== windows: %d sites" % len(sites))
for n, (start, _tgt) in enumerate(sites):
    if n % 400 == 0:
        prog("   site %d/%d stores=%d" % (n, len(sites), len(stores)))
    lo = max(tva, start - WINDOW_BACK)
    code = rd(lo, (start - lo) + WINDOW_FWD)
    regs = {}
    for ins in md.disasm(code, lo):
        if ins.id == 0:
            continue
        mn, ops = ins.mnemonic, ins.operands
        if mn == "lea" and len(ops) == 2 and ops[1].type == X86.X86_OP_MEM \
                and ops[1].mem.base == X86.X86_REG_RIP:
            tgt = ins.address + ins.size + ops[1].mem.disp
            regs[md.reg_name(ops[0].reg)] = ("va", tgt)
            if tgt in dt_at:
                dt_leas.append((ins.address, tgt))
            continue
        if mn in ("mov", "movabs") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG:
            r = md.reg_name(ops[0].reg)
            if ops[1].type == X86.X86_OP_IMM:
                regs[r] = ("imm", ops[1].imm & 0xFFFFFFFFFFFFFFFF)
            elif ops[1].type == X86.X86_OP_REG:
                regs[r] = regs.get(md.reg_name(ops[1].reg))
            else:
                regs[r] = None
        elif mn in ("xorps", "pxor") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG and ops[0].reg == ops[1].reg:
            regs[md.reg_name(ops[0].reg)] = ("imm", 0)
        elif mn == "xor" and len(ops) == 2 and ops[0].type == X86.X86_OP_REG \
                and ops[1].type == X86.X86_OP_REG and ops[0].reg == ops[1].reg:
            regs[md.reg_name(ops[0].reg)] = ("imm", 0)
        elif ops and ops[0].type == X86.X86_OP_REG and mn in (
                "xor", "add", "sub", "and", "or", "shl", "shr", "imul", "inc",
                "dec", "not", "neg", "movzx", "movsxd", "movsx", "bswap"):
            regs[md.reg_name(ops[0].reg)] = None
        if ops and ops[0].type == X86.X86_OP_MEM \
                and ops[0].mem.base == X86.X86_REG_RIP:
            dst = ins.address + ins.size + ops[0].mem.disp
            w = ops[0].size
            val = None
            if len(ops) == 2:
                if ops[1].type == X86.X86_OP_IMM:
                    val = ops[1].imm & 0xFFFFFFFFFFFFFFFF
                else:
                    r = reg_of(ops[1])
                    got = regs.get(r) if r else None
                    if got and got[0] in ("imm", "va"):
                        val = got[1]
            if w >= 1:
                stores[(ins.address, dst)] = (w, val)
p("## stores: %d, with value: %d" % (len(stores),
                                     sum(1 for v in stores.values() if v[1] is not None)))
p("## DT_ leas: %d over %d distinct" % (len(dt_leas), len({t for _, t in dt_leas})))

# ---------------------------------------------------------------------------
# rebuild the .data image from the captured stores
# ---------------------------------------------------------------------------
img = {}
for (iva, dst), (w, val) in sorted(stores.items()):
    if val is None:
        for k in range(w):
            img[dst + k] = None
    else:
        for k in range(w):
            img[dst + k] = (val >> (8 * k)) & 0xFF


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


slots = []                       # (ins_va, dst, name_str)
for (iva, dst), (w, val) in sorted(stores.items()):
    if w == 8 and val is not None and val in name_at:
        slots.append((iva, dst, name_at[val]))
slots.sort()
p("## name slots: %d over %d distinct dst" % (len(slots), len({d for _, d, _ in slots})))

# DT_* leas per function -> owning class of the array a function initializes
dt_by_func = defaultdict(list)
for iva, dtva in sorted(set(dt_leas)):
    f = func_of(iva)
    if f:
        dt_by_func[f[0]].append((iva, dtva))


def class_for(iva):
    f = func_of(iva)
    if not f:
        return None, 0, None
    cand = dt_by_func.get(f[0], [])
    if not cand:
        return None, 0, f
    before = [c for c in cand if c[0] <= iva]
    pick = before[-1] if before else cand[0]
    return dt_at[pick[1]], len({t for _, t in cand}), f


# ---------------------------------------------------------------------------
# layout scoring: where does the record start relative to the name store?
# ---------------------------------------------------------------------------
CANDS = (-0x38, -0x40, -0x30, -0x20, -0x10, -0x08, 0x00, 0x08)


def plausible(off, size):
    if off is None or size is None:
        return False
    if off % 4 or off >= 0x10000:
        return False
    if size in (1, 2):
        return True
    return 4 <= size <= 0x1000 and size % 4 == 0


def score(bva, dst):
    h0, h1 = i32(bva), i32(bva + 4)
    s = 0
    if u64(bva + 0x38) == dst:
        s += 2
    elif u64(bva) == dst:
        s += 1
    if h0 == -1 and h1 == 1:
        s += 2
    elif h0 == -1 or h1 == 1:
        s += 1
    off, size = u32(bva + 0x14), u32(bva + 0x1c)
    if plausible(off, size):
        s += 3
    td = u64(bva + 0x08)
    if td == 0 or td in ident:
        s += 1
    return s, h0, h1, off, size


records = []
pick_count = Counter()
for iva, dst, nm in slots:
    best = None
    for c in CANDS:
        s, h0, h1, off, size = score(dst + c, dst)
        if best is None or s > best[0]:
            best = (s, c, h0, h1, off, size)
    s, c, h0, h1, off, size = best
    pick_count[c] += 1
    cls, ndt, f = class_for(iva)
    records.append(dict(ins=iva, base=dst + c, cand=c, score=s, name=nm,
                        cls=cls, ndt=ndt, hdr=(h0, h1), off=off, size=size,
                        flags=u32(dst + c + 0x20), tdesc=u64(dst + c + 0x08)))

p("## best base candidate distribution (relative to name store):")
for c, n in pick_count.most_common():
    p("     %+#5x : %5d" % (c, n))
p("## score histogram: %s" % dict(Counter(r["score"] for r in records).most_common()))

strong = [r for r in records if r["score"] >= 7]
p("## strong records (score>=7): %d ; with class: %d"
  % (len(strong), sum(1 for r in strong if r["cls"])))
p("## distinct classes seen: %d" % len({r["cls"] for r in strong if r["cls"]}))

# ---------------------------------------------------------------------------
# chain records with the 0x68 stride into arrays
# ---------------------------------------------------------------------------
bybase = {}
for r in strong:
    bybase.setdefault(r["base"], r)

bases = sorted(bybase)
chains = []
cur = []
for b in bases:
    if cur and b - cur[-1] != 0x68:
        chains.append(cur)
        cur = []
    cur.append(b)
if cur:
    chains.append(cur)
p("## chains: %d ; records in chains: %d" %
  (len(chains), sum(len(c) for c in chains)))

chain_info = []
for ch in chains:
    recs = [bybase[b] for b in ch]
    cls_votes = Counter(r["cls"] for r in recs if r["cls"])
    cls = cls_votes.most_common(1)[0][0] if cls_votes else None
    hdr = next((r["name"] for r in recs if r["name"].startswith("DT_")), None)
    chain_info.append((ch[0], len(recs), cls, hdr, recs))
p("## chains with class: %d ; with DT_ header record: %d"
  % (sum(1 for c in chain_info if c[2]), sum(1 for c in chain_info if c[3])))

# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------
ANCHORS = ["m_iHealth", "m_iMaxHealth", "m_iTeamNum", "m_vecOrigin",
           "m_lifeState", "m_hOwnerEntity", "m_iName", "m_localOrigin",
           "m_vecAbsOrigin", "m_iSignifierName", "m_currentFramePlayer"]

p("")
p("#" * 70)
p("### every record for the anchor fields")
for a in ANCHORS:
    hits = [r for r in records if r["name"] == a]
    p("")
    p("%s  (%d sites)" % (a, len(hits)))
    for r in sorted(hits, key=lambda r: (str(r["cls"]), r["base"])):
        p("    cls=%-34s cand=%+#4x base=%#x hdr=(%s,%s) off=%s size=%s flags=%s score=%d ndt=%d"
          % (r["cls"], r["cand"], r["base"], r["hdr"][0], r["hdr"][1],
             ("%#x" % r["off"]) if r["off"] is not None else "-",
             r["size"], r["flags"], r["score"], r["ndt"]))

p("")
p("#" * 70)
p("### arrays (chains) that contain an anchor field")
seen_chain = set()
for a in ANCHORS:
    for r in records:
        if r["name"] != a:
            continue
        for c0, nrec, cls, hdr, recs in chain_info:
            if c0 <= r["base"] < c0 + 0x68 * nrec:
                key = (c0, a)
                if key in seen_chain:
                    continue
                seen_chain.add(key)
                p("")
                p("--- chain %#x  fields=%d  class=%s  hdr=%s  (anchor %s)"
                  % (c0, nrec, cls, hdr, a))
                for rr in sorted(recs, key=lambda rr: (rr["off"] if rr["off"] is not None else -1)):
                    p("    %#06x  size %-4s  %-40s flags=%s"
                      % (rr["off"] if rr["off"] is not None else 0,
                         rr["size"], rr["name"], rr["flags"]))

p("")
p("#" * 70)
p("### raw record bytes for the anchor sites")
for a in ANCHORS:
    for r in records:
        if r["name"] != a or r["cand"] != -0x38:
            continue
        p("")
        p("%s @ base %#x  cls=%s" % (a, r["base"], r["cls"]))
        for off in (0x00, 0x04, 0x08, 0x10, 0x14, 0x18, 0x1c, 0x20, 0x24, 0x30, 0x38):
            b = get(r["base"] + off, 8)
            if b is None:
                p("      +%02x  (unknown)" % off)
                continue
            v = struct.unpack("<Q", b)[0]
            ann = ""
            if v in ident:
                ann = "  '%s'" % ident[v]
            elif v < 0x100000:
                ann = "  (=%d)" % v
            p("      +%02x  %#018x%s" % (off, v, ann))

# ---------------------------------------------------------------------------
# full TSV dump: class, field, offset, size, flags
# ---------------------------------------------------------------------------
lines = ["class\tfield\toffset\tsize\tflags\tbase"]
for c0, nrec, cls, hdr, recs in sorted(chain_info, key=lambda c: str(c[2])):
    for rr in recs:
        lines.append("%s\t%s\t%#x\t%s\t%s\t%#x"
                     % (cls or ("?hdr:" + (hdr or "?")), rr["name"],
                        rr["off"] if rr["off"] is not None else 0, rr["size"],
                        rr["flags"], rr["base"]))
with open(os.path.join(HERE, "dm10_fields.tsv"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
p("")
p("## wrote dm10_fields.tsv: %d rows" % (len(lines) - 1))

with open(os.path.join(HERE, "dm10.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
prog("== done, %d lines" % len(out))
