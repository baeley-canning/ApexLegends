r"""p73_pe.py -- read SizeOfImage/timestamp from the on-disk exe (no device)."""
import os
import struct

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_p73_pe.txt")

with open(EXE, "rb") as f:
    h = f.read(0x400)
e = struct.unpack_from("<I", h, 0x3C)[0]
sig = h[e:e + 4]
ts = struct.unpack_from("<I", h, e + 8)[0]
machine = struct.unpack_from("<H", h, e + 4)[0]
chars = struct.unpack_from("<H", h, e + 0x16)[0]
size = struct.unpack_from("<I", h, e + 0x50)[0]
base = struct.unpack_from("<Q", h, e + 0x30)[0]
lines = ["file=%s bytes=%d" % (EXE, os.path.getsize(EXE)),
         "sig=%r machine=%#x chars=%#x ts=%#x" % (sig, machine, chars, ts),
         "SizeOfImage=%#x ImageBase=%#x" % (size, base)]
with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print("\n".join(lines))
