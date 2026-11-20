"""go21_pehdr.py -- read-only PE header probe for the live game exe (R6: scripted, no chat one-liners).
Answers ONE question before the qk_image RAM sweep: is the new build's SizeOfImage inside
qk_image.py's acceptance band (0x0DF00000..0x0E100000)?
"""
import os
import struct
import time

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"


def main():
    with open(EXE, "rb") as fh:
        h = fh.read(4096)
    assert h[:2] == b"MZ", "no MZ"
    lf = struct.unpack_from("<I", h, 0x3C)[0]
    pe = h[lf:lf + 4]
    size = struct.unpack_from("<I", h, lf + 0x50)[0]
    stamp = struct.unpack_from("<I", h, lf + 8)[0]
    machine = struct.unpack_from("<H", h, lf + 4)[0]
    print("RESULT: mz=ok pe=%r machine=0x%X" % (pe, machine))
    print("RESULT: stamp=0x%X sizeofimage=0x%X" % (stamp, size))
    ok = 0x0DF00000 <= size <= 0x0E100000
    print("RESULT: band_ok=%s (qk_image band 0x0DF00000..0x0E100000)" %
          ("YES" if ok else "NO"))
    print("RESULT: exe_mtime=%s" % time.strftime("%Y-%m-%d %H:%M:%S",
                                                 time.localtime(os.path.getmtime(EXE))))
    print("VERDICT: %s" % ("BAND-OK sweep may proceed" if ok else "BAND-MISS widen qk_image"))


if __name__ == "__main__":
    main()
