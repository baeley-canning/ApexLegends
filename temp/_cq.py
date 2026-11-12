"""Calibrate EPROCESS field offsets off the known corpse page at 0x33bcb0000."""
import sys, numpy as np
sys.path.insert(0, "..\\ext")
import gio

g = gio.Gio(chunk=0x2000)
b, e = g.read_phys(0x33bcb0000, 0x2000)
print("read:", e, len(b) if b else 0)
if b:
    for name in (b"r5apex_dx12.exe", b"r5apex_d"):
        i = b.find(name)
        print("name %-16r -> %s" % (name, hex(i) if i >= 0 else "absent"))
    for p in (22280, 69149):
        hits = [hex(k) for k in range(0, 0x800, 4) if int(np.frombuffer(b[k:k+4], "<u4")[0]) == p]
        print("pid %d -> %s" % (p, hits or "absent"))
    q = np.frombuffer(b[:0x800], "<u8")
    print("frame-like qwords:", [(hex(k), hex(int(q[k // 8])))
                                 for k in range(0, 0x600, 8) if q[k // 8] & 0xFFF == 0 and 0 < q[k // 8] < g.ram_top])
