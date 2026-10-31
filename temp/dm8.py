"""Reconstruct the schema field registry by simulating its initializer stores.

dm7 showed the registry is filled by straight-line code:
    lea   rax, [rip+"m_vecOrigin"]      ; name
    movups [rec+0x00], xmm0             ; zero record
    mov   [rec+0x08], rax               ; store the name pointer
    ... mov [rec+off], imm              ; fieldOffset / fieldSize / flags

So: disassemble a window around every field-name lea, track register values
(mov reg,imm / lea reg,[rip+x]), collect every RIP-relative store together with
its value, then apply them in address order into a copy of .data.  The result is
the registry image as it looks at runtime.

Output: temp/dm8.txt   (store census + raw record dumps around known names)
"""
import os
import re
import struct
from collections import defaultdict

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
out = []


def p(s=""):
    out.append(s)
    with open(os.path.join(HERE, "dm8_prog.txt"), "a", encoding="utf-8") as fh:
        fh.write(s + "\n")


def prog(msg):
    with open(os.path.join(HERE, "dm8_prog.txt"), "a", encoding="utf-8") as fh:
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


def cstr(va, n=64):
    b = rd(va, n)
    z = b.find(b"\x00")
    return None if z <= 0 else b[:z].decode("latin1", "replace")


# ---------------------------------------------------------------------------
# strings -> field-name VAs
# ---------------------------------------------------------------------------
ident = {}
pat = re.compile(rb"[\x20-\x7e]{3,96}")
for nm, sva, vs, rs, rp, ch in secs:
    if ch & 0x20 or rs > 0x800000:      # skip code; skip the 188MB .data
        continue
    blob = data[rp:rp + rs]
    for m in pat.finditer(blob):
        e = m.end()
        if e < rs and blob[e] == 0 and m.group()[:1].isalpha():
            ident[sva + m.start()] = m.group().decode("latin1")
names = {v: k for k, v in ident.items() if v.startswith("m_")}
name_at = {k: v for k, v in ident.items() if v.startswith("m_")}

ts = next(s for s in secs if s[5] & 0x20)
text = data[ts[4]:ts[4] + ts[3]]
tva = ts[1]
p("## %d field names, .text %#x..%#x" % (len(names), tva, tva + len(text)))

# ---------------------------------------------------------------------------
# find lea sites onto field names
# ---------------------------------------------------------------------------
sites = []
leapat = re.compile(rb"[\x48\x4c\x49\x4d]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]")
for m in leapat.finditer(text):
    i = m.start()
    d = struct.unpack_from("<i", text, i + 3)[0]
    tgt = tva + i + 7 + d
    if tgt in name_at:
        sites.append((tva + i, tgt))
p("## lea sites: %d over %d distinct names"
  % (len(sites), len({t for _, t in sites})))

# ---------------------------------------------------------------------------
# simulate the initializer: window-disassemble, track registers, collect stores
# ---------------------------------------------------------------------------
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
md.skipdata = True
X86 = capstone.x86

stores = {}          # (va, dst) -> (size, value);  value None = unknown
WINDOW_BACK, WINDOW_FWD = 0x300, 0x400


def reg_of(op):
    if op.type == X86.X86_OP_REG:
        return md.reg_name(op.reg)
    return None


def imm_of(op):
    if op.type == X86.X86_OP_IMM:
        return op.imm & 0xFFFFFFFFFFFFFFFF
    return None


seen = set()
prog("== start windows: %d sites" % len(sites))
for _n, (start, _tgt) in enumerate(sites):
    if _n % 400 == 0:
        prog("   site %d/%d stores=%d" % (_n, len(sites), len(stores)))
    lo = max(tva, start - WINDOW_BACK)
    startseen = len(stores)
    code = rd(lo, (start - lo) + WINDOW_FWD)
    regs = {}
    for ins in md.disasm(code, lo):
        if ins.id == 0:          # skipdata pseudo-instruction (no operands)
            continue
        mn, ops = ins.mnemonic, ins.operands
        # --- track register values -------------------------------------
        if mn == "lea" and len(ops) == 2 and ops[1].type == X86.X86_OP_MEM \
                and ops[1].mem.base == X86.X86_REG_RIP:
            regs[md.reg_name(ops[0].reg)] = ("va", ins.address + ins.size + ops[1].mem.disp)
        elif mn in ("mov", "movabs") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG:
            r = md.reg_name(ops[0].reg)
            if ops[1].type == X86.X86_OP_IMM:
                regs[r] = ("imm", ops[1].imm & 0xFFFFFFFFFFFFFFFF)
            elif ops[1].type == X86.X86_OP_REG:
                regs[r] = regs.get(md.reg_name(ops[1].reg))
            else:
                regs[r] = None
        elif mn in ("xorps", "pxor", "xor") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG and ops[1].type == X86.X86_OP_REG \
                and ops[0].reg == ops[1].reg:
            regs[md.reg_name(ops[0].reg)] = ("imm", 0)
        elif mn in ("xor", "add", "sub", "and", "or", "shl", "shr", "imul", "inc",
                    "dec", "not", "neg", "movzx", "movsxd", "movsx") \
                and ops and ops[0].type == X86.X86_OP_REG:
            regs[md.reg_name(ops[0].reg)] = None
        # --- record rip-relative stores --------------------------------
        if ops and ops[0].type == X86.X86_OP_MEM \
                and ops[0].mem.base == X86.X86_REG_RIP:
            dst = ins.address + ins.size + ops[0].mem.disp
            w = ops[0].size
            val = None
            if len(ops) == 2:
                val = imm_of(ops[1])
                if val is None:
                    r = reg_of(ops[1])
                    if r is not None:
                        got = regs.get(r)
                        if got and got[0] == "imm":
                            val = got[1]
                        elif got and got[0] == "va":
                            val = got[1]
            if w >= 1:
                stores[(ins.address, dst)] = (w, val)
p("## collected %d rip-relative store sites" % len(stores))
p("## with known value: %d" % sum(1 for v in stores.values() if v[1] is not None))

# ---------------------------------------------------------------------------
# apply the stores, in address order, into a .data image
# ---------------------------------------------------------------------------
dsec = next(s for s in secs if s[0] == ".data")
_, dva, dvs, drs, drp, _ = dsec
img = bytearray(max(dvs, drs))
img[:drs] = data[drp:drp + drs]

applied = 0
for (va, dst), (w, val) in sorted(stores.items()):
    if val is None:
        continue
    if not (dva <= dst and dst + w <= dva + len(img)):
        continue
    img[dst - dva:dst - dva + w] = (val & ((1 << (8 * w)) - 1)).to_bytes(w, "little")
    applied += 1
p("## applied %d stores into .data image" % applied)


def q(va):
    d = va - dva
    if not (0 <= d and d + 8 <= len(img)):
        return 0
    return struct.unpack_from("<Q", img, d)[0]


def d32(va):
    d = va - dva
    if not (0 <= d and d + 4 <= len(img)):
        return 0
    return struct.unpack_from("<i", img, d)[0]

# ---------------------------------------------------------------------------
# name-pointer slots: stores whose value is a known m_* string
# ---------------------------------------------------------------------------
name_slots = {}
for (va, dst), (w, val) in stores.items():
    if w == 8 and val in name_at:
        name_slots[dst] = name_at[val]
p("## name-pointer slots resolved: %d" % len(name_slots))

ks = sorted(name_slots)
gaps = defaultdict(int)
for a, b in zip(ks, ks[1:]):
    gaps[b - a] += 1
p("## most common slot gaps: %s" % sorted(gaps.items(), key=lambda kv: -kv[1])[:6])

# ---------------------------------------------------------------------------
# dump raw records around names of interest
# ---------------------------------------------------------------------------
interesting = ["m_iHealth", "m_iTeamNum", "m_vecOrigin", "m_lifeState",
               "m_iMaxHealth", "m_hOwnerEntity"]
by_name = defaultdict(list)
for slot, nm in name_slots.items():
    by_name[nm].append(slot)

for nm in interesting:
    p("")
    for slot in sorted(by_name.get(nm, []))[:2]:
        p("### %s  name-slot %#x   (record window %#x..%#x)"
          % (nm, slot, slot - 0x10, slot + 0x70))
        for off in range(-0x10, 0x78, 8):
            a = slot + off
            p("   %+#05x %#012x  q=%#018x  i32=%d,%d"
              % (off, a, q(a), d32(a), d32(a + 4)))
        c = cstr(q(slot)) if q(slot) else None
        p("   name@+0 -> %r" % c)

with open(os.path.join(HERE, "dm8.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm8.txt (%d lines)" % len(out))
