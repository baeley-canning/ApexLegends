import importlib.util
import struct

spec = importlib.util.spec_from_file_location(
    "dl", r"c:\Users\New User\OneDrive\Desktop\cheating\ext\dumplive.py")
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)

DTB = 0x3ABE738C0
PDPT, PDT, LEAF = 0x3000000, 0x4000000, 0x5000000


class L(object):
    ram_top = 0x800000000

    def is_ram(self, pa):
        return 0x1000 <= pa < self.ram_top

    def read_phys(self, pa, n):
        b = bytearray(n)
        if pa == DTB & dl.MASK:
            struct.pack_into("<Q", b, 0, PDPT | 1)
        elif pa == PDPT:
            struct.pack_into("<Q", b, 0, PDT | 1)
        elif pa == PDT:
            struct.pack_into("<Q", b, 0, LEAF | 1)
        print("read %#x n=%#x -> %r" % (pa, n, bytes(b[:8])))
        return bytes(b)


w = dl.Walk(L(), DTB)
print("pdpt_pa", hex(w.pdpt_pa), "e0", hex(w.e0))
print(dl.probe_dtb(L(), DTB))
