# p43u - offline unit test for the 26200 layout (no device, no elevation).
#
# p43u_a1 proved every p43q hit ends in NUL: the 16-byte pattern only ever saw
# copies, never an _EPROCESS whose ImageFileName[15] is full.  The gate must
# therefore (a) scan 15 bytes, (b) recover the base at hit-0x338, (c) still see
# the name there, (d) survive a wrong layout, and (e) find hits on pages that
# only become readable when a faulted 64 KiB chunk is retried at 4 KiB.
import importlib.util
import os
import struct
import sys

SRC = r"C:\Users\New User\OneDrive\Desktop\cheating\ext\dumplive.py"
spec = importlib.util.spec_from_file_location("dl", SRC)
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)

dl.PROG = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "p43u_test_prog.txt")
open(dl.PROG, "w").close()

PID = 5488
DTB = 0x3ABE738C0                 # logged DTB: PCID 0x8c0, frame 0x3abe73000
PAGE_PA = 0x312862000
OFF = 0x400
BASE_IN_BUF = 0x1000 + OFF - 0x338
BUF = bytearray(0x2000)


def put_obj(buf, base, pid_off=0x1d0, pc=2, name=True):
    buf[base] = 3                                   # dispatcher Type: Process
    struct.pack_into("<Q", buf, base + 0x28, DTB)   # DirectoryTableBase
    struct.pack_into("<I", buf, base + pid_off, PID)
    struct.pack_into("<Q", buf, base + 0x258, 0xFFFFA401B2EF1258)
    struct.pack_into("<Q", buf, base + 0x260, 0xFFFFA401B2EF1260)
    struct.pack_into("<Q", buf, base + 0x248, 0xFFFFA401B2EF2248)
    struct.pack_into("<Q", buf, base + 0x2e0, 0x000000D1A2B3C000)
    if name:
        buf[base + 0x338:base + 0x338 + len(dl.NAME)] = dl.NAME
    buf[base + 0x347] = pc


put_obj(BUF, BASE_IN_BUF)


class FakeG(object):
    ram_top = 0x800000000
    chunk = 0x10000

    def is_ram(self, pa):
        return 0x100000 <= pa < self.ram_top

    def read_phys(self, pa, n):
        if pa != PAGE_PA - 0x1000:
            raise OSError("unexpected read %#x n=%#x" % (pa, n))
        return bytes(BUF)


dl.LOG = []
assert dl.valid_cr3(FakeG(), DTB), "PCID dtb wrongly rejected"
assert not dl.valid_cr3(FakeG(), 0), "zero dtb accepted"
assert not dl.valid_cr3(FakeG(), 0x800000000), "dtb above ram_top accepted"
print("P43U_CR3_GATE")

c = dl.candidates_for(FakeG(), PID, [PAGE_PA + OFF])
print("candidates:", c)
ok = (len(c) == 1 and c[0][1] == PAGE_PA + OFF - 0x338 and c[0][2] == DTB
      and c[0][0] >= 18)
print("P43U_ONE_GOOD_CANDIDATE" if ok else "P43U_FAIL")

# 26200 has UniqueProcessId at +0x1d0; +0x1a4 is the edge of the drift window
# and must still pass while the name check holds the base.
BUF2 = bytearray(0x2000)
put_obj(BUF2, BASE_IN_BUF, pid_off=0x1A4)


class FakeE(FakeG):
    def read_phys(self, pa, n):
        return bytes(BUF2)


e = dl.candidates_for(FakeE(), PID, [PAGE_PA + OFF])
print("window-edge candidates:", e)
oke = len(e) == 1 and e[0][1] == PAGE_PA + OFF - 0x338
print("P43U_PID_WINDOW_EDGE" if oke else "P43U_FAIL")
ok = ok and oke

# a 16-byte copy (NUL after the name) with no pid must not become a base
BUF3 = bytearray(0x2000)
BUF3[BASE_IN_BUF + 0x338:BASE_IN_BUF + 0x338 + 15] = dl.NAME


class Fake3(FakeG):
    def read_phys(self, pa, n):
        return bytes(BUF3)


c3 = dl.candidates_for(Fake3(), PID, [PAGE_PA + OFF])
print("copy-only candidates:", c3)
ok3 = not c3
print("P43U_COPY_REJECTED" if ok3 else "P43U_FAIL")
ok = ok and ok3

# pid present but DTB lane zero -> reject, the frame stays the verdict
BUF4 = bytearray(BUF)
struct.pack_into("<Q", BUF4, BASE_IN_BUF + 0x28, 0)


class Fake4(FakeG):
    def read_phys(self, pa, n):
        return bytes(BUF4)


c4 = dl.candidates_for(Fake4(), PID, [PAGE_PA + OFF])
print("zero-dtb candidates:", c4)
ok4 = not c4
print("P43U_ZERO_DTB_REJECTED" if ok4 else "P43U_FAIL")
ok = ok and ok4


# an old-layout object: name still at base+0x4c8 and no name at +0x338 must
# fail, or the gate would resurrect the pre-26200 geometry.
BUF5 = bytearray(0x2000)
B5 = 0x1000 + 0x400 - 0x4C8
put_obj(BUF5, B5, pid_off=0x440, name=False)
BUF5[B5 + 0x4C8:B5 + 0x4C8 + 15] = dl.NAME

# a faulted BACK page must not throw the candidate away when the base sits in
# the hit page (offset >= 0x338); with the base in the back page it must.
FB = bytearray(0x1000)                     # hit page only
put_obj(FB, 0x400 - 0x338)                 # base at page offset 0xc8


class FakeB(FakeG):
    def read_phys(self, pa, n):
        if n == 0x2000:
            raise OSError("back page pair faulted")
        return bytes(FB)


b = dl.candidates_for(FakeB(), PID, [PAGE_PA + 0x400])
print("back-fault candidates:", b)
okb = len(b) == 1 and b[0][1] == PAGE_PA + 0x400 - 0x338
print("P43U_BACKFAULT_FALLBACK" if okb else "P43U_FAIL")
ok = ok and okb

# same fault, but the hit only 0x180 into the page: the base is in the missing
# back page, so nothing may be produced.
h2 = dl.candidates_for(FakeB(), PID, [PAGE_PA + 0x180])
print("back-fault low-hit candidates:", h2)
okb2 = not h2
print("P43U_BACKFAULT_LOW_HIT" if okb2 else "P43U_FAIL")
ok = ok and okb2



class Fake5(FakeG):
    def read_phys(self, pa, n):
        return bytes(BUF5)


c5 = dl.candidates_for(Fake5(), PID, [PAGE_PA + OFF])
print("old-layout candidates:", c5)
ok5 = not c5
print("P43U_OLD_LAYOUT_REJECTED" if ok5 else "P43U_FAIL")
ok = ok and ok5

# --hex must expose the base region: type at rel=-0x338, DTB at -0x310 and the
# PriorityClass byte (top byte of the qword at rel=+0x08).
dl.LOG = []
dl.hex_probe(FakeG(), [PAGE_PA + OFF])
hdr = dl.LOG[0]
rows = dl.LOG
print("hex header:", hdr)
row338 = [l for l in rows if "rel=-0x338" in l]
row310 = [l for l in rows if "rel=-0x310" in l]
row008 = [l for l in rows if "rel=+0x008" in l]
print("type row:", row338[0] if row338 else "MISSING")
print("pc row:", row008[0] if row008 else "MISSING")
okh = bool("-0x3a0..+0x40" in hdr and row338 and row310 and row008)
print("hex parts: hdr=%s r338=%d r310=%d r008=%d rows=%d"
      % ("-0x3a0..+0x40" in hdr, len(row338), len(row310), len(row008),
         len([l for l in rows if "rel=" in l])))
if okh:
    okh = ((int(row338[0].split()[-1], 16) & 0xFF) == 3
           and ("%016x" % DTB) in row310[0]
           and (int(row008[0].split()[-1], 16) >> 56) == 2
           and len([l for l in rows if "rel=" in l]) == 125)
print("P43U_HEX_BASE_WINDOW" if okh else "P43U_FAIL")
ok = ok and okh

# ---------------------------------------------------------------- fault rescue
# A bad 4 KiB page used to cost the whole 64 KiB chunk.  The model faults every
# >4 KiB read, one isolated page (0x101000) and all of the second chunk; the two
# hits -- one straddling 0x102ffe -> 0x103000 -- must still be found.
MODEL_LO, MODEL_HI = 0x100000, 0x110000
MODEL = bytearray(MODEL_HI - MODEL_LO)
BAD = {0x101000} | set(range(0x108000, 0x110000, 0x1000))


def mput(pa, data):
    MODEL[pa - MODEL_LO:pa - MODEL_LO + len(data)] = data


mput(0x102000, dl.NAME)
mput(0x102FFE, dl.NAME)


class Faulty(object):
    ram_top = 0x10000000

    def is_ram(self, pa):
        return MODEL_LO <= pa < MODEL_HI

    def read_phys(self, pa, n):
        if n > dl.PAGE:
            raise OSError("chunk fault")
        if pa in BAD or not (MODEL_LO <= pa < MODEL_HI):
            raise OSError("page fault")
        return bytes(MODEL[pa - MODEL_LO:pa - MODEL_LO + n])


h, sk, ch, rs = dl.name_hits(Faulty(), [(MODEL_LO, MODEL_HI)], chunk=0x8000)
print("rescue hits:", ["%#x" % x for x in h], "skipped=%d rescued=%d chunks=%d"
      % (sk, rs, ch))
okr = h == [0x102000, 0x102FFE] and sk == 9 and rs == 7 and ch == 2
print("P43U_FAULT_RESCUE" if okr else "P43U_FAIL")
ok = ok and okr

tail = open(dl.PROG, encoding="utf-8").read()
print("prog tail:", tail.strip().splitlines()[-1])
okp = "SCANEND" in tail and "rescued=7" in tail
print("P43U_PROG_RESCUE_COUNT" if okp else "P43U_FAIL")
ok = ok and okp

print("P43U_ALL_OK" if ok else "P43U_FAIL")
sys.exit(0 if ok else 1)
