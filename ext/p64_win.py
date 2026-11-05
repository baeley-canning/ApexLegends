r"""p64_win.py -- print the float neighbourhood of a physical address.

p64 hands out base+offset; deciding what the offset *is* needs the neighbours,
not another statistical guess.  Read-only, one page max per base, clamped so a
read never crosses into an unmapped page.

Usage: python ext\p64_win.py 0x6c6af0864 [--lo=0x40] [--n=0x80]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402


def fl32(b):
    return struct.unpack("<%df" % (len(b) // 4), b)


def main(argv):
    bases, lo, n = [], 0x40, 0x80
    for a in argv:
        if a.startswith("--lo="):
            lo = int(a[5:], 0)
        elif a.startswith("--n="):
            n = int(a[4:], 0)
        elif not a.startswith("--"):
            bases += [int(x, 0) for x in a.split(",") if x]
    if not bases:
        print("usage: p64_win.py BASE[,BASE..] [--lo=0x40] [--n=0x80]")
        return 2
    g = gio.Gio(chunk=0x1000)
    try:
        for b in bases:
            start = b - lo
            start &= ~0x3                       # float-align the window
            if (start & ~0xFFF) != ((start + n - 1) & ~0xFFF):
                n = 0x1000 - (start & 0xFFF)
            try:
                data = g.read_phys(start, n)
            except OSError as e:
                print("BASE %#x FAULT at %#x err=%d" % (b, start, e.errno or -1))
                continue
            print("BASE %#x win=%#x..%#x (hit=%#x)" % (b, start, start + n, b - start))
            for i in range(0, len(data), 16):
                row = data[i:i + 16]
                fs = fl32(row)
                iv = struct.unpack("<%di" % (len(row) // 4), row)
                print(" %+#06x f %s | i %s"
                      % (start + i - b, " ".join("%.4g" % f for f in fs),
                         " ".join(str(v) for v in iv)))
        print("RESULT dumped=%d" % len(bases))
        return 0
    finally:
        g.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
