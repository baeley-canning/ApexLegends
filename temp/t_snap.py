import os
import sys
import traceback

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ext"))
import gio  # noqa: E402

print("start", flush=True)
g = gio.Gio()
print("handle ok", flush=True)
base = 0x4D006A119 & ~0xFFF
for k in (-2, -1, 0, 1, 2):
    p = base + k * 0x1000
    try:
        b = g.read_phys(p, 0x1000)
        print("ok %#x len=%d first16=%s" % (p, len(b), b[:16].hex()), flush=True)
    except Exception as e:
        print("err %#x %s: %s" % (p, type(e).__name__, e), flush=True)
        traceback.print_exc()
print("end", flush=True)
