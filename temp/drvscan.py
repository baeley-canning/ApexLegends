"""drvscan.py -- pull candidate IOCTL constants out of the two signed drivers.

IOCTL codes live in .text as `cmp eax, imm32` / `mov ecx, imm32` immediates, so
just look for 4-byte little-endian values whose high word is the CTL_CODE type
(0x50 0xc3 = 0xC350xxxx for gdrv3, 0x10 0x80 = 0x8010xxxx for MsIo64) and print
them with a little context.
"""
import os
import struct
import sys

TARGETS = [
    (r"C:\Windows\System32\drivers\gdrv3.sys", b"\x50\xc3"),
    (r"C:\Windows\System32\drivers\MsIo64.sys", b"\x10\x80"),
]


def main():
    out = []
    for path, hi in TARGETS:
        data = open(path, "rb").read()
        out.append("== %s  size=%d" % (os.path.basename(path), len(data)))
        seen = set()
        for i in range(len(data) - 4):
            if data[i + 2:i + 4] != hi:
                continue
            val = struct.unpack_from("<I", data, i)[0]
            if val in seen:
                continue
            seen.add(val)
            ctx = data[max(0, i - 6):i + 10]
            out.append("  %#010x  at %#x  ctx %s"
                       % (val, i, ctx.hex()))
        out.append("  total distinct: %d" % len(seen))
    open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "drvscan.txt"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
