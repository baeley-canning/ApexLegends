import importlib.util
import struct

spec = importlib.util.spec_from_file_location(
    "dl", r"c:\Users\New User\OneDrive\Desktop\cheating\ext\dumplive.py")
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)

LEAF, PDT = 0x5000000, 0x4000000
pt = bytearray(0x1000)
struct.pack_into("<Q", pt, 0, LEAF | 1)
pte = dl.u64(pt, 0)
print("pte", hex(pte), "present", pte & 1, "ram", dl.MASK and (LEAF & dl.MASK))
print("isram", 0x1000 <= (pte & dl.MASK) < 0x800000000)
print("src has 60000:", "leaf > 60000" in open(
    r"c:\Users\New User\OneDrive\Desktop\cheating\ext\dumplive.py").read())
