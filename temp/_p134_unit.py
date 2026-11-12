r"""offline unit check for _p134.scan: partner filter must keep array members, drop singles."""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import _p134 as P

BUF = bytearray(0x10000)


def put(off, v):
    struct.pack_into("<fff", BUF, off, *v)


put(0x1000, (6000.0, 2.0, -5000.0))     # pair, 0xC8 apart  -> kept
put(0x10C8, (6000.0, 2.0, -5200.0))
put(0x2000, (6100.0, 2.0, -5100.0))     # isolated          -> dropped
put(0x3000, (6200.0, 2.0, -5300.0))     # pair, 0xC0 apart  -> kept
put(0x30C0, (6200.0, 2.0, -5500.0))
put(0x4000, (6300.0, 7000.0, -5600.0))  # y out of bounds   -> dropped
put(0x40C8, (6310.0, 7000.0, -5610.0))
put(0x5000, (1.0, 1.0, 1.0))            # too small         -> dropped
put(0x5080, (2.0, 2.0, 2.0))            # partner too small -> dropped

a, v = [], []
P.scan(bytes(BUF), 0x10000000, "float", a, v)
addrs = [int(x) - 0x10000000 for x in a[0]] if a else []
print("hits:", [hex(x) for x in addrs])
want = {0x1000, 0x10C8, 0x3000, 0x30C0}
got = set(addrs)
print("want:", sorted(map(hex, want)))
print("PASS" if got == want else "FAIL missing=%s extra=%s"
      % (sorted(map(hex, want - got)), sorted(map(hex, got - want))))
sys.exit(0 if got == want else 1)
