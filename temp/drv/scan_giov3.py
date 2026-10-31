"""scan_giov3.py -- find user-mode binaries that reference the GIOV3 device.

Scans for the UTF-16 (and ASCII) pattern 'GIOV3' / 'MsIo' inside code
binaries under a few roots and lists the hits with a small hex context so
the matching CreateFileW / DeviceIoControl constants can be read off.
"""
import io
import os
import sys

ROOTS = [r"C:\Program Files\GIGABYTE", r"C:\Program Files (x86)\GIGABYTE"]
NEEDLES = ["GIOV3", "MsIo", "gdrv", "MAPPHYS", "\\\\.\\"]
EXTS = (".exe", ".dll", ".sys", ".ocx", ".cpl", ".dat", ".json")


def hexdump(data, lo, hi):
    lines = []
    for i in range(lo, hi, 16):
        chunk = data[i:i + 16]
        lines.append("      %08x  %-47s  %s"
                     % (i, " ".join("%02x" % c for c in chunk),
                        "".join(chr(c) if 32 <= c < 127 else "." for c in chunk)))
    return lines


def main():
    out = []
    n_files = 0
    for root in ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            for fn in filenames:
                if not fn.lower().endswith(EXTS):
                    continue
                p = os.path.join(dirpath, fn)
                try:
                    if os.path.getsize(p) > 20 * 1024 * 1024:
                        continue
                    data = open(p, "rb").read()
                except OSError:
                    continue
                hits = [n for n in NEEDLES
                        if n.encode("utf-16-le") in data or n.encode() in data]
                if not hits:
                    continue
                n_files += 1
                out.append("=== %s  [%s]" % (p, ",".join(hits)))
                for n in hits:
                    for enc, tag in ((n.encode("utf-16-le"), "w"), (n.encode(), "a")):
                        start = 0
                        while True:
                            off = data.find(enc, start)
                            if off < 0:
                                break
                            start = off + 1
                            out.append("   -- %s %r @ %#x" % (tag, n, off))
                            out += hexdump(data, max(0, off - 0x20), off + 0x30)
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "giov3_scan.txt")
    io.open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote %s (%d files hit)" % (dst, n_files))


main()



def hexdump(data, base, lo, hi):
    lines = []
    for i in range(lo, hi, 16):
        chunk = data[i:i + 16]
        lines.append("      %08x  %-47s  %s"
                     % (base + i, " ".join("%02x" % c for c in chunk),
                        "".join(chr(c) if 32 <= c < 127 else "." for c in chunk)))
    return lines


def main():
    out = []
    for root in ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d.lower() not in
                           ("winsxs", "assembly", "driverstore", "temp", "__pycache__")]
            for fn in filenames:
                if not fn.lower().endswith(EXTS):
                    continue
                p = os.path.join(dirpath, fn)
                try:
                    if os.path.getsize(p) > 160 * 1024 * 1024:
                        continue
                    data = open(p, "rb").read()
                except OSError:
                    continue
                hits = [n for n in NEEDLES
                        if n.encode("utf-16-le") in data or
                        (len(n) > 4 and n.encode() in data)]
                if not hits:
                    continue
                out.append("=== %s  [%s]" % (p, ",".join(hits)))
                for n in hits:
                    for enc, tag in ((n.encode("utf-16-le"), "w"), (n.encode(), "a")):
                        if len(n) <= 4 and tag == "a":
                            continue
                        start = 0
                        while True:
                            off = data.find(enc, start)
                            if off < 0:
                                break
                            start = off + 1
                            out.append("   -- %s %r @ %#x" % (tag, n, off))
                            out += hexdump(data, 0, max(0, off - 0x40), off + 0x40)
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "giov3_scan.txt")
    io.open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote %s (%d files hit)" % (dst, sum(1 for l in out if l.startswith("==="))))


main()
