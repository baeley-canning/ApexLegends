# p59_hold.py -- hold a 64 MiB touched allocation containing NEEDLE so an
# out-of-process scanner can find it. Prints nothing, sleeps, frees on exit.
import ctypes
import sys
import time

MB = int(sys.argv[1]) if len(sys.argv) > 1 else 64
HOLD = float(sys.argv[3]) if len(sys.argv) > 3 else 300.0
NEEDLE = b'P59NEEDLE-0123456789'
k32 = ctypes.windll.kernel32
k32.VirtualAlloc.restype = ctypes.c_void_p
k32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong,
                             ctypes.c_ulong]

size = MB << 20
p = k32.VirtualAlloc(None, ctypes.c_size_t(size), 0x3000, 4)
if not p:
    raise SystemExit('alloc failed')
buf = (ctypes.c_char * size).from_address(p)
buf[0:len(NEEDLE)] = NEEDLE
for off in range(0, size, 0x1000):
    buf[off] = 0x42
for off in range(0, size - len(NEEDLE), 0x4000):
    ctypes.memmove(p + off, NEEDLE, len(NEEDLE))
open(sys.argv[2], 'w').write('ready\n')
time.sleep(HOLD)
