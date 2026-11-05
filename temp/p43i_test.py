# p43i - offline unit test for candidates_for() (no device, no elevation).
# p43h read the real bytes: the pid sits at rel=-0x088 on nine solo pages, i.e.
# base+0x440 with base=hit-0x4c8, and the name at base+0x4c8.  The old -0x5a8
# delta therefore sees no pid at all, so only the corrected geometry may yield a
# candidate.  The DTB is a real logged value carrying a PCID in its low bits.
import importlib.util
import struct
import sys

SRC = r"C:\Users\New User\OneDrive\Desktop\cheating\ext\dumplive.py"
spec = importlib.util.spec_from_file_location("dl", SRC)
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)

PID = 5488
DTB = 0x3ABE738C0                 # logged DTB: PCID 0x8c0, frame 0x3abe73000
PAGE = 0x312862000
OFF = 0x180                       # name offset inside the hit page
BASE_IN_BUF = 0x1000 + OFF - 0x4C8
BUF = bytearray(0x2000)
BUF[BASE_IN_BUF] = 3              # _DISPATCHER_HEADER.Type == ProcessObject
BUF[BASE_IN_BUF + 0x4C8:BASE_IN_BUF + 0x4C8 + len(dl.NAME)] = dl.NAME
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x28, DTB)
struct.pack_into("<I", BUF, BASE_IN_BUF + 0x440, PID)
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x448, 0xFFFFA401B2EF1448)
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x450, 0xFFFFA401B2EF1450)


class FakeG(object):
    ram_top = 0x800000000
    chunk = 0x10000

    def is_ram(self, pa):
        return 0x100000 <= pa < self.ram_top

    def read_phys(self, pa, n):
        if pa != PAGE - 0x1000:
            raise OSError("unexpected read %#x n=%#x" % (pa, n))
        return bytes(BUF)


dl.LOG = []
# PCID gate: the raw DTB is not page aligned but its frame is RAM.
assert dl.valid_cr3(FakeG(), DTB), "PCID dtb wrongly rejected"
assert not dl.valid_cr3(FakeG(), 0), "zero dtb accepted"
assert not dl.valid_cr3(FakeG(), 0x800000000), "dtb above ram_top accepted"
print("P43I_CR3_GATE")

c = dl.candidates_for(FakeG(), PID, [PAGE + OFF])
print("candidates:", c)
ok = (len(c) == 1 and c[0][1] == PAGE + OFF - 0x4C8 and c[0][2] == DTB
      and c[0][0] == 8)
print("P43I_ONE_GOOD_CANDIDATE" if ok else "P43I_FAIL")

# the hex probe must expose the DTB lane (base+0x28 -> rel=-0x4a0) and print
# both windows: head below the hit, the pid/name tail around it.
dl.LOG = []
dl.hex_probe(FakeG(), [PAGE + OFF])
hdr = dl.LOG[0]
rows = [l for l in dl.LOG if "rel=-0x4a0" in l]
print("hex header:", hdr)
print("hex dtb row:", rows[0] if rows else "MISSING")
okh = ("-0x600..-0x480" in hdr and "-0x110..+0x40" in hdr and rows
       and ("%016x" % DTB) in rows[0]
       and len([l for l in dl.LOG if "rel=" in l]) == 49 + 43)
print("P43I_HEX_HEAD_WINDOW" if okh else "P43I_FAIL")
ok = ok and okh

# old assumption would place the base 0xe0 lower; no pid there, so a wrong
# NAME_DELTAS entry can no longer shadow the true one.
print("old-delta base:", hex(PAGE + OFF - 0x5A8))
print("P43I_OLD_DELTA_DIFFERS" if PAGE + OFF - 0x4C8 != PAGE + OFF - 0x5A8
      else "P43I_FAIL")

# junk links: delta bonus alone must survive at score 4.
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x448, 0x1234)
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x450, 0x5678)
j = dl.candidates_for(FakeG(), PID, [PAGE + OFF])
print("junk-link candidates:", j)
print("P43I_JUNK_LINK_SCORE" if j and j[0][0] == 4 else "P43I_FAIL")

# p43k regression: the walk must read the masked frame, never frame|PCID.
class Rec(object):
    ram_top = 0x800000000

    def __init__(self):
        self.seen = []

    def is_ram(self, pa):
        return 0x1000 <= pa < self.ram_top

    def read_phys(self, pa, n):
        self.seen.append(pa)
        return bytes(0x1000)

    def u64(self, pa):
        return 0


rec = Rec()
w = dl.Walk(rec, DTB)
print("walk first read:", ", ".join("%#x" % s for s in rec.seen), "raw:", hex(w.raw))
print("P43K_WALK_MASKS_CR3" if rec.seen == [0x3ABE73000] else "P43I_FAIL")
ok = ok and rec.seen == [0x3ABE73000]

# p43m regression: a hit 3 bytes before the page end must not unpack past the
# 0x2000 buffer; the unaligned tail is reported as bytes instead.
class Flat(object):
    ram_top = 0x800000000

    def is_ram(self, pa):
        return 0x1000 <= pa < self.ram_top

    def read_phys(self, pa, n):
        return bytes(n)


dl.LOG = []
dl.hex_probe(Flat(), [PAGE + 0xFFD])
tail = [l for l in dl.LOG if "tail" in l]
print("page-end rows:", len([l for l in dl.LOG if "rel=" in l]),
      "tails:", len(tail), (tail[:1] or ["MISSING"])[0])
print("P43M_PAGE_END_TAIL" if len(tail) == 1 and "tail 3 bytes" in tail[0]
      else "P43I_FAIL")
ok = ok and len(tail) == 1 and "tail 3 bytes" in tail[0]

# negative control: pid dword removed -> no candidate.
struct.pack_into("<I", BUF, BASE_IN_BUF + 0x440, 0)
c2 = dl.candidates_for(FakeG(), PID, [PAGE + OFF])
print("control candidates:", len(c2))
print("P43I_CONTROL_EMPTY" if not c2 else "P43I_CONTROL_FAIL")
ok = ok and not c2

# ------------------------------------------------------------------ p43o
# p43p counted the real pid at rel=-0x084 on twenty dumped blocks, i.e. +0x444
# from base, which an 8-step PID_OFFS window steps over.  A 4-step window must
# see it, and the DTB lane must still be what picks the base (only +0x28 holds a
# frame), so the unaligned pid alone may not create a base.
BUF2 = bytearray(0x2000)
struct.pack_into("<Q", BUF2, BASE_IN_BUF + 0x28, DTB)
struct.pack_into("<I", BUF2, BASE_IN_BUF + 0x444, PID)          # unaligned
struct.pack_into("<Q", BUF2, BASE_IN_BUF + 0x448, 0xFFFFA401B2EF1448)
struct.pack_into("<Q", BUF2, BASE_IN_BUF + 0x450, 0xFFFFA401B2EF1450)


class Fake2(FakeG):
    def read_phys(self, pa, n):
        return bytes(BUF2)


u = dl.candidates_for(Fake2(), PID, [PAGE + OFF])
print("unaligned-pid candidates:", u)
oku = (len(u) == 1 and u[0][1] == PAGE + OFF - 0x4C8 and u[0][2] == DTB)
print("P43O_UNALIGNED_PID" if oku else "P43I_FAIL")
ok = ok and oku

# a multi-hit page used to collapse to min(hit), so only the lowest hit could
# ever name a base.  Two copies on one page, pid+dtb only under the SECOND hit:
# the candidate must come from hit 2 and the dump must contain both blocks.
H1, H2 = PAGE + 0x180, PAGE + 0x900
B2 = bytearray(0x2000)
for hh in (H1, H2):
    B2[0x1000 + hh - PAGE:0x1000 + hh - PAGE + len(dl.NAME)] = dl.NAME
BASE2 = 0x1000 + H2 - PAGE - 0x4C8
B2[BASE2 + 0x28:BASE2 + 0x30] = struct.pack("<Q", DTB)
B2[BASE2 + 0x440:BASE2 + 0x444] = struct.pack("<I", PID)
B2[BASE2 + 0x448:BASE2 + 0x450] = struct.pack("<Q", 0xFFFFA401B2EF1448)
B2[BASE2 + 0x450:BASE2 + 0x458] = struct.pack("<Q", 0xFFFFA401B2EF1450)


class Fake3(FakeG):
    def read_phys(self, pa, n):
        return bytes(B2)


m = dl.candidates_for(Fake3(), PID, [H1, H2])
print("multi-hit candidates:", m)
okm = len(m) == 1 and m[0][1] == H2 - 0x4C8
print("P43O_SECOND_HIT_BASE" if okm else "P43I_FAIL")
ok = ok and okm

dl.LOG = []
dl.hex_probe(Fake3(), [H1, H2])
blocks = [l for l in dl.LOG if l.startswith("  == hit=")]
print("multi-hit blocks:", len(blocks), blocks[:1] or ["MISSING"])
okx = (len(blocks) == 2 and "hit=2/2" in blocks[1]
       and "solo=0 multi=1" in dl.LOG[0] and "hit=1/2" in blocks[0])
print("P43O_MULTI_PAGE_DUMP" if okx else "P43I_FAIL")
ok = ok and okx

# probe_dtb must split "no PE": absent PML4 entry, non-RAM PDPT, and RAM leaves
# without any MZ page are three different verdicts, not one.
class NoPml4(object):
    ram_top = 0x800000000

    def is_ram(self, pa):
        return 0x1000 <= pa < self.ram_top

    def read_phys(self, pa, n):
        return bytes(n)


pb = dl.probe_dtb(NoPml4(), DTB)
print("probe absent:", pb)
okp = "pml4[0]=0000000000000000" in pb and "not-ram/absent" in pb


class NoRam(NoPml4):
    def read_phys(self, pa, n):
        b = bytearray(n)
        struct.pack_into("<Q", b, 0, 0x1)          # present, frame 0
        return bytes(b)


pb2 = dl.probe_dtb(NoRam(), DTB)
print("probe non-ram pdpt:", pb2)
okp = okp and "pdpt not-ram" in pb2

LEAF = 0x5000000                 # PT frame
DATA = 0x6000000                 # 4 KiB data frame, deliberately not "MZ"
PDT = 0x4000000
PDPT = 0x3000000


class Leaves(NoPml4):
    """pml4[0] -> pdpt -> pd -> pt -> one RAM leaf that is not an MZ page."""

    def read_phys(self, pa, n):
        b = bytearray(n)
        if pa == DTB & dl.MASK:
            struct.pack_into("<Q", b, 0, PDPT | 1)
        elif pa == PDPT:
            struct.pack_into("<Q", b, 0, PDT | 1)
        elif pa == PDT:
            struct.pack_into("<Q", b, 0, LEAF | 1)
        elif pa == LEAF:
            struct.pack_into("<Q", b, 0, DATA | 1)
        elif pa == DATA:
            return b"PO"
        return bytes(b)


pb3 = dl.probe_dtb(Leaves(), DTB)
print("probe leaves:", pb3)
okp = okp and "leaf=1 mz=0" in pb3
print("P43O_WHY_SPLIT" if okp else "P43I_FAIL")
ok = ok and okp

sys.exit(0 if ok else 1)
