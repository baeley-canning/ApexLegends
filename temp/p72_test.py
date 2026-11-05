"""p72_test.py -- offline unit test of p72_ppath stage chain.

Synthetic address space, no driver, no elevation.  Proves the BFS arithmetic
(including a negative hop), the PA-page compare, the live re-walk and the
verdict line, which is where a silent bug would otherwise only show up after
a 70 s scan.

Usage: python temp\p72_test.py
"""
import os
import struct
import sys
import types

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))

os.environ["DUMP_OUT"] = "p72_test_out.txt"
os.environ["DUMP_PROG"] = "p72_test_prog.txt"
import p72_ppath as p  # noqa: E402

BASE = 0x7FF600000000
SEC_VA = 0x1000
SEED_OFF = 0x100
HOP = 0x20
TARGET = 0x420B0A000
NEG_HOP = HOP - SEED_OFF          # chain hop is relative to the node's page

# data: seed qword -> 0x400000100; at that VA +0x20 -> 0x410000500
data = bytearray(0x2000)
struct.pack_into("<Q", data, SEED_OFF, 0x400000100)
heap = {}
heap[0x400000000] = bytearray(0x1000)
struct.pack_into("<Q", heap[0x400000000], HOP, 0x410000500)
heap[0x410000000] = bytearray(0x1000)
struct.pack_into("<f", heap[0x410000000], 0x500, 123.5)

PA = {0x7FF600000000: 0x2F0000000, 0x7FF600001000: 0x300000000,
      0x400000000: 0x3F0000000, 0x410000000: TARGET}
PAGES = {0x2F0000000: bytearray(0x1000), 0x300000000: data,
         0x3F0000000: heap[0x400000000], TARGET: heap[0x410000000]}


class FakeG(object):
    def __init__(self, chunk=0x10000):
        self.chunk = chunk

    def read_phys(self, pa, n):
        pg = pa & ~0xFFF
        off = pa & 0xFFF
        if pg not in PAGES:
            raise OSError(1450, "phys read %#x failed" % pa)
        return bytes(PAGES[pg][off:off + n])

    def is_ram(self, pa):
        return True

    def close(self):
        pass


class FakeWalk(object):
    def __init__(self, g, cr3):
        self.g, self.cr3 = g, cr3

    def page_pa(self, va):
        return PA.get(va & ~0xFFF)


def run():
    p.gio = types.SimpleNamespace(Gio=FakeG)
    p.dl.Walk = FakeWalk
    p.dl.pid_alive = lambda pid: True
    p.MAP = os.path.join(ROOT, "temp", "p72_test_map.txt")
    p.DATA = os.path.join(ROOT, "temp", "p72_test_data.bin")
    open(p.DATA, "wb").write(bytes(data))
    sha = __import__("hashlib").sha256(bytes(data)).hexdigest()
    p.write_map([("PID", 12092), ("TARGET", "%#x" % TARGET),
                 ("BASE", "%#x" % BASE), ("DTB", "0x570000000"),
                 ("SEC", ".data"), ("SEC_VA", "%#x" % SEC_VA),
                 ("SEC_SIZE", "%#x" % len(data)), ("TAKE", "%#x" % len(data)),
                 ("FILE", p.DATA), ("SHA", sha), ("PID_START", "test")])
    code = p.stage_chain()
    out = open(p.OUT, encoding="utf-8").read()
    print(out)
    ok = (code == 0 and "VERDICT: CHAIN" in out
          and ("%+#x" % NEG_HOP) in out and "ok=1" in out
          and "~123.500" in out)
    print("TEST %s code=%d expected_hop=%+#x" % ("PASS" if ok else "FAIL",
                                                 code, NEG_HOP))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(run())
