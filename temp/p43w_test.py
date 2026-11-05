"""p43w unit test - shape() only, no device (pidscan imports gio, not Gio)."""
import importlib.util
import struct
import sys

SRC = r"C:\Users\New User\OneDrive\Desktop\cheating\ext\pidscan.py"
spec = importlib.util.spec_from_file_location("ps", SRC)
ps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ps)

PID = 0x1570
DTB = 0x3ABE738C0
buf = bytearray(0x4000)
BASE, OFF = 0x2000, 0x1D0
I = BASE + OFF
buf[BASE] = 3
struct.pack_into("<Q", buf, BASE + 0x28, DTB)
struct.pack_into("<I", buf, I, PID)
struct.pack_into("<Q", buf, BASE + 0x258, 0xFFFFA401B2EF11D8)
struct.pack_into("<Q", buf, BASE + 0x260, 0xFFFFA401B2EF11E0)
struct.pack_into("<Q", buf, BASE + 0x248, 0xFFFFA401B2EF2248)
struct.pack_into("<Q", buf, BASE + 0x2E0, 0x000000D1A2B3C000)
buf[BASE + 0x347] = 2


class G(object):
    ram_top = 0x800000000

    def is_ram(self, pa):
        return 0x100000 <= pa < self.ram_top


r = list(ps.shape(G(), buf, I))
print("shape:", r)
ok = (len(r) == 1 and r[0][0] == 0x1D0 and r[0][2] == DTB and r[0][3] >= 18)
print("P43W_SHAPE_OK" if ok else "P43W_FAIL")

# tyte byte above 6 would be a different object class
buf2 = bytearray(buf)
buf2[BASE] = 9
print("shape type9:", list(ps.shape(G(), buf2, I)))
ok2 = not list(ps.shape(G(), buf2, I))
print("P43W_TYPE_REJECT" if ok2 else "P43W_FAIL")
sys.exit(0 if ok and ok2 else 1)
