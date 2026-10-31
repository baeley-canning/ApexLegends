"""
dm32: statically reconstruct EVERY datamap typedescription array straight from
the unrolled initializer store streams (dm31 proved a single one works; this
does the whole image).

Discovery
    the initializers are found by scanning .text for `lea rX,[rip+d]` whose
    target is a "DT_*" string, grouped by the .pdata function containing them.

Reconstruction
    every rip-relative absolute store inside that function is replayed into a
    byte image of its target, in instruction order, with a light constant
    propagation over the registers (lea/mov imm/movabs/xor/pxor/movups).
    Because the compilers fuse pairs of 32-bit fields into `mov qword [x], imm`
    (offset in the low half, size in the high half) the byte image -- not a
    per-field dict -- is what makes the records readable.

Record template (0x68 stride), confirmed against the live .data sample:
    +0x00 fieldType     +0x04 offset      +0x0c size       +0x14 flags
    +0x20 type-desc     +0x28 m_* name    +0x48 save/restore helper
    +0x58 -1             +0x5c 1           +0x60 secondary name
The array a class registers starts one slot AFTER the sentinel slot that holds
"should_never_see_this"; the registration call itself is

    RegisterClass(rcx = class descriptor, rdx = &array[1],
                  r8d = numFields, r9 = "DT_...")

which is used as the cross-check.

Usage: python dm32.py [--cls DT_Name] [--fn 0x...] [--quiet]
Output: temp/dm32.txt, temp/dm32_fields.tsv
"""
import bisect
import os
import re
import struct
import sys

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
IMGBASE = 0x140000000
STRIDE = 0x68
VALID = {0x00, 0x04, 0x08, 0x0c, 0x10, 0x14, 0x18, 0x1c, 0x20, 0x24,
         0x28, 0x2c, 0x30, 0x34, 0x38, 0x3c, 0x40, 0x44, 0x48, 0x4c,
         0x50, 0x54, 0x58, 0x5c, 0x60, 0x64}

pe = pefile.PE(PATH, fast_load=True)
raw = open(PATH, "rb").read()
secs = [(s.Name.rstrip(b"\x00").decode("latin1"), IMGBASE + s.VirtualAddress,
         s.Misc_VirtualSize, s.SizeOfRawData, s.PointerToRawData)
        for s in pe.sections]

out = []


def p(s=""):
    out.append(s)
    if not QUIET:
        print(s)


QUIET = False


def sec_of(va):
    for s in secs:
        if s[1] <= va < s[1] + max(s[2], s[3]):
            return s
    return None


def secname(va):
    s = sec_of(va)
    return "?" if s is None else "%s+%#x" % (s[0], va - s[1])


def read_va(va, n):
    s = sec_of(va)
    if s is None:
        return None
    d = va - s[1]
    if d + n > s[3]:
        return None
    return raw[s[4] + d:s[4] + d + n]


def cstr(va, n=96):
    b = read_va(va, 1)
    if b is None:
        return None
    s = sec_of(va)
    o = s[4] + (va - s[1])
    e = raw.find(b"\x00", o, o + n)
    if e < 0:
        return None
    try:
        t = raw[o:e].decode("ascii")
    except UnicodeDecodeError:
        return None
    return t if t and all(32 <= ord(c) < 127 for c in t) else None


# every string in the data sections, keyed by its virtual address
STR = {}
for _s in secs:
    if _s[0] not in (".rdata", ".data"):
        continue
    _blob = raw[_s[4]:_s[4] + _s[3]]
    for _m in re.finditer(rb"[\x20-\x7e]{4,}", _blob):
        if _m.end() < len(_blob) and _blob[_m.end()] == 0:
            STR[_s[1] + _m.start()] = _m.group().decode("latin1")


def string_at(va):
    if va is None:
        return None
    t = STR.get(va)
    if t is not None:
        return t
    return cstr(va)


# --- function table from .pdata -------------------------------------------
FUNCS = []
for _s in secs:
    if _s[0] != ".pdata":
        continue
    _blob = raw[_s[4]:_s[4] + _s[3]]
    for _i in range(0, len(_blob) - 11, 12):
        _b, _e, _u = struct.unpack_from("<III", _blob, _i)
        if _b and _e:
            FUNCS.append((IMGBASE + _b, IMGBASE + _e))
FUNCS.sort()
_STARTS = [f[0] for f in FUNCS]


def func_at(va):
    i = bisect.bisect_right(_STARTS, va) - 1
    if i >= 0 and FUNCS[i][0] <= va < FUNCS[i][1]:
        return FUNCS[i]
    return None


TEXT = next(s for s in secs if s[0] == ".text")


def lea_sites(lo, hi):
    """yield (insn_va, target_va) for every `lea r64, [rip+disp]`."""
    blob = raw[TEXT[4] + (lo - TEXT[1]):TEXT[4] + (hi - TEXT[1])]
    for m in re.finditer(rb"[\x48\x4c\x49\x4d]\x8d", blob):
        i = m.start()
        if i + 7 > len(blob):
            break
        if (blob[i + 2] & 0xC7) != 0x05:
            continue
        disp = struct.unpack_from("<i", blob, i + 3)[0]
        va = lo + i
        yield va, va + 7 + disp


t_lo, t_hi = TEXT[1], TEXT[1] + max(TEXT[2], TEXT[3])
DT_BY_FUNC = {}
for _iva, _tva in lea_sites(t_lo, t_hi):
    _n = STR.get(_tva)
    if not _n or not _n.startswith("DT_"):
        continue
    _f = func_at(_iva)
    if _f:
        DT_BY_FUNC.setdefault(_f[0], []).append((_iva, _tva, _n))

p("=" * 92)
p("## dm32: static datamap reconstruction")
p("=" * 92)
p("  image       : %s" % PATH)
p("  sections    : %s" % ", ".join("%s %#x" % (s[0], s[2]) for s in secs))
p("  strings     : %d" % len(STR))
p("  functions   : %d (.pdata)" % len(FUNCS))
p("  DT_ leas    : %d in %d functions"
  % (sum(len(v) for v in DT_BY_FUNC.values()), len(DT_BY_FUNC)))

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True

# capstone reports r8d/ecx/... as distinct ids; fold every sub-register onto
# its 64-bit parent so a `mov r8d, 0x10` is visible as a write to r8.
_ALIAS = {}
for _b in (["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"] +
           ["r%d" % i for i in range(8, 16)]):
    for _v in ({"rax": ["eax", "ax", "al"], "rcx": ["ecx", "cx", "cl"],
                "rdx": ["edx", "dx", "dl"], "rbx": ["ebx", "bx", "bl"],
                "rsp": ["esp", "sp", "spl"], "rbp": ["ebp", "bp", "bpl"],
                "rsi": ["esi", "si", "sil"], "rdi": ["edi", "di", "dil"]
                }.get(_b) or [_b + "d", _b + "w", _b + "b"]):
        try:
            _ALIAS[getattr(capstone.x86, "X86_REG_" + _v.upper())] = \
                getattr(capstone.x86, "X86_REG_" + _b.upper())
        except AttributeError:
            pass


def norm(r):
    return _ALIAS.get(r, r)


TRACE = None
DUMP = False
DISLIMIT = 100


def hexr(flat, va, n):
    """hex row of raw store-image bytes, '--' where nothing was written"""
    return " ".join("%02x" % flat[va + i] if va + i in flat else "--"
                    for i in range(n))


class RegMap(dict):
    """register file that transparently folds sub-registers"""
    def __getitem__(self, k):
        return dict.__getitem__(self, norm(k))

    def __setitem__(self, k, v):
        dict.__setitem__(self, norm(k), v)

    def get(self, k, d=None):
        return dict.get(self, norm(k), d)


def runs(fn):
    """disassemble one function, tracking just enough constants to resolve the
    operand of every absolute store, and replay those stores into a byte image
    of the target range."""
    lo, hi = fn
    s = sec_of(lo)
    blob = raw[s[4] + (lo - s[1]):s[4] + (hi - s[1])]
    insns = list(md.disasm(blob, lo))
    # where control can arrive from elsewhere -> drop all register knowledge
    branch_dst = set()
    for ins in insns:
        for op in ins.operands:
            if op.type == capstone.x86.X86_OP_IMM and \
                    ins.group(capstone.x86.X86_GRP_JUMP):
                branch_dst.add(op.imm)

    reg = RegMap()   # reg id -> ('va'|'imm'|'sym'|'mem', value[, delta])
    seen_dst = set()
    mem = {}      # target va -> (bytearray(16) value, bytearray(16) written)
    flat = {}     # target va -> final byte value (last write wins)
    rflat = {}    # call-site sym -> {relative offset: byte}
    GSYM = {}     # absolute global va -> (sym, delta): pointer parked in .data
    stores = []   # (insn_va, target, width, kind, value)
    calls = []    # (insn_va, {arg: value})

    def killed():
        reg.clear()

    def put(addr, width, buf):
        if addr is None:
            return
        if isinstance(addr, tuple):
            # relative to a symbolic base (array allocated at runtime)
            d = rflat.setdefault(addr[0], {})
            for i in range(width):
                d[addr[1] + i] = buf[i]
            return
        cur = mem.get(addr)
        if cur is None:
            cur = (bytearray(16), bytearray(16))
            mem[addr] = cur
        val, wr = cur
        for i in range(width):
            val[i] = buf[i]
            wr[i] = 1
            flat[addr + i] = buf[i]

    n = 0
    for ins in insns:
        n += 1
        if ins.address in branch_dst and ins.address != lo and \
                ins.address not in seen_dst:
            # first arrival at a join: nothing to merge against yet, and the
            # fall-through path (which is what a linear sweep walks) is the
            # live one.  register writes and call clobbers handle the rest.
            seen_dst.add(ins.address)
        m = ins.mnemonic
        ops = ins.operands
        if m in ("ret", "int3") and n > 4:
            # not a terminator for a *linear* sweep: the initialiser body is
            # often laid out after the guard's cold path, so keep walking the
            # whole .pdata range and just forget the register file.
            killed()

        def mem_val(op):
            """resolve a memory operand to a va (or a (sym, offset) pair)"""
            if op.type != capstone.x86.X86_OP_MEM:
                return None
            if op.mem.base == capstone.x86.X86_REG_RIP:
                return ins.address + ins.size + op.mem.disp
            if op.mem.base and op.mem.index == 0:
                b = reg.get(op.mem.base)
                if b and b[0] in ("va", "imm"):
                    return b[1] + op.mem.disp
                if b and b[0] == "sym":
                    return (b[1], b[2] + op.mem.disp)
            return None

        def rval(op):
            if op.type == capstone.x86.X86_OP_REG:
                return reg.get(op.reg)
            if op.type == capstone.x86.X86_OP_IMM:
                return ("imm", op.imm)
            return None

        # ---- constant propagation ------------------------------------------
        if m == "lea" and len(ops) == 2 and ops[0].type == \
                capstone.x86.X86_OP_REG:
            t = mem_val(ops[1])
            reg[ops[0].reg] = ("va", t) if t is not None else None
        elif m in ("mov", "movabs") and len(ops) == 2:
            d, src = ops[0], ops[1]
            if d.type == capstone.x86.X86_OP_REG:
                if src.type == capstone.x86.X86_OP_IMM:
                    reg[d.reg] = ("imm", src.imm)
                elif src.type == capstone.x86.X86_OP_REG:
                    reg[d.reg] = reg.get(src.reg)
                elif src.type == capstone.x86.X86_OP_MEM:
                    t = mem_val(src)
                    if isinstance(t, tuple):
                        reg[d.reg] = ("sym", t[0], t[1])
                    elif t in GSYM:
                        reg[d.reg] = ("sym", GSYM[t][0], GSYM[t][1])
                    else:
                        reg[d.reg] = ("mem", t) if t is not None else None
            elif d.type == capstone.x86.X86_OP_MEM:
                t, w, v = mem_val(d), d.size, rval(src)
                if v and v[0] in ("va", "imm") and v[1] is not None:
                    stores.append((ins.address, t, w, v[0], v[1]))
                    put(t, w, (v[1] & ((1 << (8 * w)) - 1)).to_bytes(w, "little"))
                elif v and v[0] == "sym":
                    # pointer to a runtime-allocated object parked in a global
                    if isinstance(t, int) and v[2] == 0:
                        GSYM[t] = (v[1], 0)
                    stores.append((ins.address, t, w, "sym", None))
                else:
                    stores.append((ins.address, t, w, "?", None))
        elif m in ("movups", "movaps", "movdqu", "movdqa", "movd", "movq") \
                and len(ops) == 2 and ops[0].type == capstone.x86.X86_OP_MEM:
            t, w, v = mem_val(ops[0]), ops[0].size, rval(ops[1])
            if v and v[0] == "imm" and v[1] == 0:
                stores.append((ins.address, t, w, "imm", 0))
                put(t, w, bytes(w))
            else:
                stores.append((ins.address, t, w, "xmm", None))
        elif m == "xorps" or m == "pxor":
            if len(ops) == 2 and ops[0].reg == ops[1].reg:
                reg[ops[0].reg] = ("imm", 0)
        elif m in ("add", "sub") and len(ops) == 2 and \
                ops[0].type == capstone.x86.X86_OP_REG and \
                ops[1].type == capstone.x86.X86_OP_IMM:
            v = reg.get(ops[0].reg)
            d = ops[1].imm if m == "add" else -ops[1].imm
            if v and v[0] in ("va", "imm") and v[1] is not None:
                reg[ops[0].reg] = (v[0], v[1] + d)
            elif v and v[0] == "sym":
                reg[ops[0].reg] = ("sym", v[1], v[2] + d)
            else:
                reg[ops[0].reg] = None

        if m == "call":
            calls.append((ins.address,
                          dict((k, reg.get(v)) for k, v in
                               (("rcx", capstone.x86.X86_REG_RCX),
                                ("rdx", capstone.x86.X86_REG_RDX),
                                ("r8", capstone.x86.X86_REG_R8),
                                ("r9", capstone.x86.X86_REG_R9)))))
            killed()
            # the return value of any call becomes a symbolic base: several
            # datamaps are allocated at runtime and only the returned pointer
            # anchors their typedescription array.
            reg[capstone.x86.X86_REG_RAX] = ("sym", ins.address, 0)
        elif m not in ("push", "pop", "nop", "lea", "mov", "movabs",
                       "movups", "movaps", "movdqu", "movdqa", "movd",
                       "movq", "xorps", "pxor", "add", "sub") and \
                ops and ops[0].type == capstone.x86.X86_OP_REG and \
                not m.startswith(("cmp", "test", "j")):
            reg[ops[0].reg] = None

        if TRACE is not None:
            def _s(rr):
                v = reg.get(rr)
                if v is None:
                    return "-"
                if v[1] is None:
                    return "%s?" % v[0]
                return "%s:%#x" % (v[0], v[1])
            TRACE.append("   %#012x  %-7s %-34s | %s %s %s %s | rdi=%s rsi=%s rbx=%s"
                         % (ins.address, m, ins.op_str,
                            _s(capstone.x86.X86_REG_RCX),
                            _s(capstone.x86.X86_REG_RDX),
                            _s(capstone.x86.X86_REG_R8),
                            _s(capstone.x86.X86_REG_R9),
                            _s(capstone.x86.X86_REG_RDI),
                            _s(capstone.x86.X86_REG_RSI),
                            _s(capstone.x86.X86_REG_RBX)))

    return flat, stores, calls, len(insns), rflat


# ---- reconstruction -------------------------------------------------------
def rd(flat, va, n):
    b = bytearray()
    for i in range(n):
        v = flat.get(va + i)
        if v is None:
            return None
        b.append(v)
    return int.from_bytes(b, "little")


def rd0(flat, va, n):
    """read n bytes treating never-written ones as 0 -- the typedesc arrays
    live in the zero-filled tail of .data, so an unwritten byte *is* zero."""
    v = 0
    for i in range(n):
        b = flat.get(va + i)
        if b is not None:
            v |= b << (8 * i)
    return v


def is_dat(va):
    s = sec_of(va)
    return s is not None and s[0] in (".data", ".bss")


def clusterize(stores):
    tg = sorted(set(s[1] for s in stores
                    if isinstance(s[1], int) and is_dat(s[1])))
    out, cur = [], []
    for t in tg:
        if cur and t - cur[-1] > 0x800:
            out.append(cur)
            cur = []
        cur.append(t)
    if cur:
        out.append(cur)
    return out


def python_name(r):
    """classify a qword that should be a name pointer"""
    if r is None:
        return "(unwritten)"
    if r == 0:
        return "(null)"
    t = string_at(r)
    if t:
        return repr(t)
    if 0x140001000 <= r < 0x143200000:
        return "%#x .text" % r
    return "%#x %s" % (r, secname(r))


FIELDS = []     # (class, idx, type, off, size, flags, name, alt, fn, desc)
CLASSES = []    # dicts


RELBASE = 0x100000000   # synthetic va used for relative (runtime) images


def rel_phase(d):
    """find the record phase of a relative image: the typedescription name
    pointer sits at +0x28, so every 8-byte run that resolves to a string
    votes for a phase."""
    votes = {}
    for off in d:
        v = 0
        for i in range(8):
            b = d.get(off + i)
            if b is None:
                v = None
                break
            v |= b << (8 * i)
        if not v or v < IMGBASE:
            continue
        s = string_at(v)
        if not s or not (s[0].isalpha() or s[0] == "_"):
            continue
        ph = (off - 0x28) % STRIDE
        votes[ph] = votes.get(ph, 0) + 1
    if not votes:
        return None, 0
    ph = max(votes, key=lambda k: votes[k])
    return ph, votes[ph]


def rel_flat(rflat):
    """choose the symbolic base that looks most like a typedescription array
    and return it as a synthetic absolute byte image."""
    best, score = None, 0
    for sym, d in rflat.items():
        ph, n = rel_phase(d)
        if n > score:
            best, score = (sym, d, ph), n
    if best is None:
        return None, None
    sym, d, ph = best
    flat = dict((RELBASE + off, b) for off, b in d.items())
    return flat, RELBASE + ph


def _one(flat, stores, args, dtname, fn, nins, relbase=None, img=None,
         hint=None):
    img = flat if img is None else img
    arr = None
    nfields = None
    desc = None
    rd_ = args.get("rdx")
    r8 = args.get("r8")
    rcx = args.get("rcx")
    if rd_ and rd_[0] == "va":
        arr = rd_[1]
    if r8 and r8[0] == "imm":
        nfields = r8[1]
    if rcx and rcx[0] == "va" and relbase is None:
        desc = rcx[1]

    if relbase is not None:
        # runtime-allocated array: records start at relbase, no sentinel
        base = relbase - STRIDE
        arr = relbase
        if nfields is None:
            while any((arr + nfields * STRIDE + k) in flat
                      for k in range(0x28, 0x30)):
                nfields += 1
            while nfields and not any((arr + (nfields - 1) * STRIDE + k) in flat
                                      for k in range(STRIDE)):
                nfields -= 1
    else:
        cl = sorted(clusterize(stores), key=lambda c: c[-1] - c[0], reverse=True)
        if arr is None:
            # the array of a lazily registered class sits in the same
            # translation unit as its name literal: align16(name + len + 1)
            # is the sentinel record and the first field follows it.
            hit = hint is not None and \
                string_at(rd0(img, hint + 0x28, 8)) == "should_never_see_this"
            if hit:
                base = hint
                arr = base + STRIDE
            else:
                if not cl:
                    return None
                # score every cluster/phase pair by how much it looks like a
                # typedescription array (small fieldType, resolvable name)
                cand = []
                for tg in cl:
                    span = (tg[-1] - tg[0]) // STRIDE + 2
                    for ph in range(0, STRIDE):
                        b = tg[0] - ph
                        sc = 0
                        for i in range(span + 1):
                            r = b + i * STRIDE
                            t = rd(img, r, 4)
                            nmv = rd(img, r + 0x28, 8)
                            if t is not None and t < 0x40:
                                sc += 1
                            if nmv and string_at(nmv):
                                sc += 2
                        cand.append((sc, b, tg[0]))
                cand.sort(reverse=True)
                base = cand[0][1]
                if DUMP:
                    p("   dbg clusters: %d, best score=%d at %#x"
                      % (len(cl), cand[0][0], base))
                    for sc, b, lo in cand[:3]:
                        p("      cand score=%-4d base=%#x lo=%#x name=%s"
                          % (sc, b, lo,
                             python_name(rd0(flat, b + 0x28, 8))))
                # grow down over records that carry field data
                while any((base - STRIDE + k) in img for k in (0, 4, 0x28)):
                    base -= STRIDE
                arr = base + STRIDE
        else:
            base = arr - STRIDE
        if nfields is None:
            nfields = 0
            while all((base + (nfields + 1) * STRIDE + 0x28 + k) in img
                      for k in range(8)):
                nfields += 1

    names = dtname or "?"
    if DUMP:
        p("   dbg %s: base=%#x arr=%#x n=%s%s"
          % (names, base, arr, nfields, " REL" if relbase else ""))
    cls = dict(dt=names, fn=fn[0], desc=desc, arr=arr, base=base,
               nfields=nfields, nins=nins, nstores=len(stores),
               rel=relbase is not None)
    rows = []
    end = arr + nfields * STRIDE
    for i in range(-1, nfields + 1):
        r = base + (i + 1) * STRIDE
        if relbase is not None and i < 0:
            continue
        if r < base or r >= end + STRIDE:
            continue
        row = dict(
            idx=i,
            va=r,
            cov=sum(1 for k in range(STRIDE) if (r + k) in img),
            type=rd0(img, r + 0x00, 4),
            off=rd0(img, r + 0x04, 4),
            size=rd0(img, r + 0x0c, 4),
            flags=rd0(img, r + 0x14, 4),
            desc=rd0(img, r + 0x20, 8),
            name=rd0(img, r + 0x28, 8),
            fn=rd0(img, r + 0x48, 8),
            alt=rd0(img, r + 0x60, 8),
            w28=all((r + 0x28 + k) in img for k in range(8)),
        )
        rows.append(row)
    cls["rows"] = rows
    cls["flat"] = img
    return cls


def builds(fn, dt_list, img=None):
    """One initialiser may register several classes back to back: split the
    store stream at each registration call.  Two flavours exist -- a direct
    RegisterClass(desc, &arr[1], n, "DT_*") and a lazy variant that passes
    only the class name to a helper and fills the array with plain
    rip-relative stores.  A single datamap is often filled by *many*
    initialiser functions, so records are read out of the merged image `img`
    while the store clustering stays local to this function."""
    flat, stores, calls, nins, rflat = fruns(fn)
    rcalls = []
    for a, args in calls:
        nm = None
        for k in ("r9", "rcx"):
            v = args.get(k)
            if v and v[0] == "va":
                t = string_at(v[1]) or ""
                if t.startswith("DT_"):
                    nm = t
                    break
        if nm:
            rcalls.append((a, args, nm))
    if not rcalls:
        # lazy flavour: the class name is only lea'd (never passed to the
        # registrar directly) and the array is filled with rip-relative
        # stores, so the name comes from the function's own DT_ string.
        out = []
        for _iva, tva, nm in dt_list:
            hint = (tva + len(nm) + 1 + 15) & ~15
            c = _one(flat, stores, {}, nm, fn, nins, img=img, hint=hint)
            if c:
                c["insn"] = nins
                out.append(c)
        return out
    res = []
    lo = fn[0]
    relflat, relbase = rel_flat(rflat)
    for a, args, t in rcalls:
        seg = [s for s in stores if lo <= s[0] < a]
        lo = a
        if args.get("rdx") is None and relflat is not None:
            seg = stores
            c = _one(relflat, seg, args, t, fn, nins, relbase, img=relflat)
        else:
            if not seg:
                seg = [s for s in stores if s[0] < a]
            if not seg:
                continue
            c = _one(flat, seg, args, t, fn, nins, img=img)
        if c:
            c["insn"] = nins
            res.append(c)
    return res


# ---- driver ---------------------------------------------------------------
# a function's store stream is independent of the merged image, so replays are
# cached and reused by every reconstruction pass
RCACHE = {}


def fruns(f):
    r = RCACHE.get(f[0])
    if r is None:
        r = RCACHE[f[0]] = runs(f)
    return r


def writers(ranges):
    """functions holding a `lea` with a target inside one of `ranges`"""
    if not ranges:
        return set()
    R = sorted(ranges)
    los = [r[0] for r in R]
    out = set()
    for iva, tva in lea_sites(t_lo, t_hi):
        i = bisect.bisect_right(los, tva) - 1
        if i < 0 or tva >= R[i][1]:
            continue
        f = func_at(iva)
        if f:
            out.add(f[0])
    return out


def main():
    global QUIET, TRACE, DUMP, DISLIMIT
    sel_cls = None
    sel_fn = None
    dbg = False
    a = sys.argv[1:]
    i = 0
    while i < len(a):
        if a[i] == "--cls" and i + 1 < len(a):
            sel_cls = a[i + 1]
            i += 2
        elif a[i] == "--fn" and i + 1 < len(a):
            sel_fn = int(a[i + 1], 16)
            i += 2
        elif a[i] == "--dbg":
            dbg = True
            i += 1
        elif a[i] == "--dis":
            TRACE = []
            dbg = True
            i += 1
        elif a[i] == "--dump":
            DUMP = True
            i += 1
        elif a[i] == "--full":
            DISLIMIT = -1
            i += 1
        elif a[i] in ("-q", "--quiet"):
            QUIET = True
            i += 1
        else:
            i += 1

    # pass 1: replay every initialiser and merge the resulting byte images --
    # the same datamap is filled by many translation units, each calling
    # RegisterClass on its own slice of the record array
    IMG = {}
    for fnva in DT_BY_FUNC:
        _f = func_at(fnva)
        if not _f:
            continue
        IMG.update(fruns(_f)[0])
    if dbg:
        p("  dbg merged image: %d bytes from %d initialisers"
          % (len(IMG), len(DT_BY_FUNC)))

    # pass 1b: arrays are often filled by functions that never mention the
    # class name (the registrar thunk holds the nfields, the field stores live
    # elsewhere).  Once a tentative array span is known, every `lea` into it
    # identifies such a writer, which is then replayed as well.
    if not sel_fn:
        rgs = []
        for _fnva, _dts in DT_BY_FUNC.items():
            for _c in builds(func_at(_fnva), _dts, IMG):
                if _c["nfields"]:
                    rgs.append((_c["arr"] - STRIDE,
                                _c["arr"] + _c["nfields"] * STRIDE))
        cand = writers(rgs)
        ex = cand - set(DT_BY_FUNC)
        for _fnva in sorted(ex):
            IMG.update(fruns(func_at(_fnva))[0])
        if dbg:
            p("  dbg inner writers: %d of %d candidates, image %d bytes"
              % (len(ex), len(cand), len(IMG)))

    allc = []
    for fnva, dts in sorted(DT_BY_FUNC.items(), key=lambda kv: kv[1][0][0]):
        if sel_fn and fnva != sel_fn:
            continue
        if dbg:
            _f = func_at(fnva)
            _fl, _st, _cl, _ni, _rf = fruns(_f)
            p("  dbg %#x-%#x: %d insn, %d stores, %d calls, %d rel-images"
              % (_f[0], _f[1], _ni, len(_st), len(_cl), len(_rf)))
            for _a, _args in _cl:
                p("     call %#x  rcx=%s rdx=%s r8=%s r9=%s"
                  % (_a, _args.get("rcx"), _args.get("rdx"),
                     _args.get("r8"), _args.get("r9")))
            if TRACE:
                p("  dbg trace (%s insn):"
                  % ("all" if DISLIMIT < 0 else "last %d" % DISLIMIT))
                for _l in (TRACE if DISLIMIT < 0 else TRACE[-DISLIMIT:]):
                    p(_l)
        cs = builds((fnva, func_at(fnva)[1]), dts, IMG)
        if not cs:
            p("  !! no registration call recovered for %s (init %#x)"
              % (dts[0][2], fnva))
        for c in cs:
            if sel_cls and c["dt"] != sel_cls:
                continue
            allc.append(c)

    p("")
    p("=" * 92)
    p("## classes")
    p("=" * 92)
    for c in allc:
        p("")
        p("### %s   init=%#x (%d insn)%s  desc=%s  array=%#x  n=%d"
          % (c["dt"], c["fn"], c["insn"], "  REL" if c.get("rel") else "",
             "-" if c["desc"] is None else "%#x" % c["desc"],
             c["arr"] or 0, c["nfields"]))
        for r in c["rows"]:
            if DUMP:
                p("   dump %#012x" % r["va"])
                for o in range(0, STRIDE, 16):
                    p("     +%02x  %s" % (o, hexr(c["flat"], r["va"] + o, 16)))
            if r["idx"] >= c["nfields"]:
                continue        # trailing slot belongs to the next array
            tag = "sentinel" if r["idx"] < 0 else "wiring  " if r["idx"] >= \
                c["nfields"] else "field %2d" % r["idx"]
            bits = []
            if r["type"] is not None:
                bits.append("t=%#06x" % r["type"])
            if r["off"] is not None:
                bits.append("off=%#07x" % r["off"])
            if r["size"] is not None:
                bits.append("sz=%#05x" % r["size"])
            if r["flags"] is not None:
                bits.append("fl=%#06x" % r["flags"])
            if r["desc"]:
                bits.append("desc=%#x" % r["desc"])
            if r["fn"]:
                bits.append("sr=%#x" % r["fn"])
            nm = python_name(r["name"])
            alt = python_name(r["alt"]) if r["alt"] is not None else "-"
            cov = "" if r["cov"] >= STRIDE else " ~%d/%d" % (r["cov"], STRIDE)
            p("   %s %#012x  %-38s %-30s %s%s"
              % (tag, r["va"], " ".join(bits), nm, "alt=" + alt, cov))
            FIELDS.append((c["dt"], r["idx"], r["type"], r["off"], r["size"],
                           r["flags"], nm.strip("'"), alt.strip("'"),
                           r["desc"], r["fn"], c["nfields"]))
        CLASSES.append(c)

    # ---- sanity ----------------------------------------------------------
    rows = sum(len(c["rows"]) for c in CLASSES)
    named = sum(1 for f in FIELDS if f[6] and "_" in f[6])
    sent = sum(1 for c in CLASSES for r in c["rows"] if r["idx"] < 0)
    over = sum(1 for c in CLASSES for r in c["rows"] if r["idx"] >= c["nfields"])
    p("")
    p("=" * 92)
    p("## summary")
    p("=" * 92)
    p("  classes        : %d" % len(CLASSES))
    p("  typedesc slots : %d (incl. %d sentinel, %d trailing wiring)"
      % (rows, sent, over))
    p("  named fields   : %d" % named)
    p("  total nfields  : %d" % sum(c["nfields"] for c in CLASSES))

    # what is the +0x60 qword, really?  test the candidate hypotheses
    same = prev = other = text = none = 0
    for c in CLASSES:
        seen = []
        for r in c["rows"]:
            if not r["alt"]:
                continue
            if r["alt"] == r["name"]:
                same += 1
            elif r["alt"] in seen:
                prev += 1
            elif 0x140001000 <= r["alt"] < 0x143200000:
                text += 1
            elif string_at(r["alt"]):
                other += 1
            else:
                none += 1
            if r["name"]:
                seen.append(r["name"])
    p("  +0x60 qword    : own-name=%d, a-previous-field-name=%d, .text=%d,"
      % (same, prev, text))
    p("                    another-string=%d, unclassified=%d"
      % (other, none))

    txt = os.path.join(HERE, "dm32.txt")
    with open(txt, "w") as fh:
        fh.write("\n".join(out) + "\n")
    tsv = os.path.join(HERE, "dm32_fields.tsv")
    with open(tsv, "w") as fh:
        fh.write("class\tidx\tfieldType\toffset\tsize\tflags\tname\talt"
                 "\ttypedesc\tfieldfn\tnfields\n")
        for f in FIELDS:
            def h(v):
                return "-" if v is None else ("%#x" % v)
            fh.write("%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\n"
                     % (f[0], f[1], h(f[2]), h(f[3]), h(f[4]), h(f[5]),
                        f[6] or "-", f[7] or "-", h(f[8]), h(f[9]), f[10]))
    p("")
    p("  -> %s" % txt)
    p("  -> %s" % tsv)


if __name__ == "__main__":
    main()


