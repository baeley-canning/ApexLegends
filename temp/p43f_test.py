# p43f - offline unit test for candidates_for() (no device, no elevation).
# The scanned NAME is _EPROCESS.ImageFileName at base+0x5a8, so the resolver must
# look BACKWARD.  Synthetic page: 1 back page + hit page, name at page+0x180,
# EPROCESS base = 0x1180-0x5a8 in the buffer, pid at base+0x440, dtb at base+0x28.
import importlib.util
import struct
import sys

SRC = r"C:\Users\New User\OneDrive\Desktop\cheating\ext\dumplive.py"
spec = importlib.util.spec_from_file_location("dl", SRC)
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)

PID = 5488
DTB = 0x1FE000000
PAGE = 0x312862000
OFF = 0x180                      # name offset inside the hit page
BASE_IN_BUF = 0x1000 + OFF - 0x5A8
BUF = bytearray(0x2000)
BUF[BASE_IN_BUF + 0x5A8:BASE_IN_BUF + 0x5A8 + len(dl.NAME)] = dl.NAME
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x28, DTB)
struct.pack_into("<I", BUF, BASE_IN_BUF + 0x440, PID)
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x448, 0xFFFFA401B2EF1448)
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x450, 0xFFFFA401B2EF1448)


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
c = dl.candidates_for(FakeG(), PID, [PAGE + OFF])
print("candidates:", c)
ok = (len(c) == 1 and c[0][1] == PAGE + OFF - 0x5A8 and c[0][2] == DTB
      and c[0][0] == 5)
print("P43F_ONE_GOOD_CANDIDATE" if ok else "P43F_FAIL")

# junk links (no KVA shape, one delta bonus left) must still pass at score 1,
# then a page with neither links nor exact delta must be dropped entirely.
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x448, 0x1234)
struct.pack_into("<Q", BUF, BASE_IN_BUF + 0x450, 0x5678)
print("junk-link candidates:", dl.candidates_for(FakeG(), PID, [PAGE + OFF]))
print("P43F_JUNK_LINK_SCORE" if dl.candidates_for(FakeG(), PID,
                                                [PAGE + OFF])[0][0] == 1
      else "P43F_FAIL")

# negative control: pid dword removed -> no candidate, and only one read needed
struct.pack_into("<I", BUF, BASE_IN_BUF + 0x440, 0)
c2 = dl.candidates_for(FakeG(), PID, [PAGE + OFF])
print("control candidates:", len(c2))
print("P43F_CONTROL_EMPTY" if not c2 else "P43F_CONTROL_FAIL")
sys.exit(0 if (ok and not c2) else 1)
