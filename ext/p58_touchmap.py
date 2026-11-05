# p58_touchmap.py -- allocate+touch N MiB, then re-run the PA ladder in the SAME
# process. If touched pages become readable, the 1450 is "page is free", not a
# bad address. Read-only w.r.t. the driver; allocation is private to this process.
import ctypes
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gio

MB = int(sys.argv[2]) if len(sys.argv) > 2 else 8192
out = sys.argv[1] if len(sys.argv) > 1 else 'temp/p58_touchmap.txt'
rows = []

k32 = ctypes.windll.kernel32
k32.VirtualAlloc.restype = ctypes.c_void_p
k32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong,
                             ctypes.c_ulong]
MEM_COMMIT_RESERVE = 0x3000
PAGE_READWRITE = 4

size = MB << 20
p = k32.VirtualAlloc(None, ctypes.c_size_t(size), MEM_COMMIT_RESERVE, PAGE_READWRITE)
rows.append('alloc=%d MiB va=%#x' % (MB, p or 0))
if p:
    buf = (ctypes.c_char * size).from_address(p)
    needle = b'p58needle'
    ctypes.memmove(p, needle, len(needle))
    step = 0x1000
    for off in range(0, size, step):
        buf[off] = 0x41
    touched = sum(1 for off in range(0, size, 0x100000) if buf[off] == b'A')
    rows.append('touched sampled=%d' % touched)

g = gio.Gio()
ok = bad = 0
for gi in range(4, 36):
    pa = gi << 30
    if pa >= g.ram_top:
        break
    try:
        b = g.read_phys(pa, 16)
        ok += 1
        rows.append('OK    %#011x %s' % (pa, b[:8].hex()))
    except OSError as e:
        bad += 1
        rows.append('FAULT %#011x err=%s' % (pa, e.args[0]))
rows.append('ok=%d fault=%d' % (ok, bad))
rows.append('END')
open(out, 'w', encoding='utf-8').write('\n'.join(rows) + '\n')
