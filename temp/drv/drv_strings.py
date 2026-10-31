"""drv_strings.py -- what do gdrv3.sys / MsIo64.sys actually expose?

We are looking for two things, straight out of the binaries:
  1. device / symbolic-link names (so we can open the right \\.\ path), and
  2. 32-bit constants that look like IOCTL codes (0x8xxxxxxx / 0xC3xxxxxx),
     which is what the dispatch routine compares DeviceIoControlCode against.

No driver is touched here; this is read-only file parsing.
"""
import os
import re
import struct
import sys

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")
TARGETS = ["gdrv3.sys", "MsIo64.sys", "MsIo64.sys"]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "drv_strings.txt")

# IOCTL-ish constants: high bit set, and the low two bits are the transfer type.
IOCTL_RE = re.compile(rb"[\x00-\xff]{0}")


def ascii_strings(buf, minlen=5):
    return re.findall(rb"[\x20-\x7e]{%d,}" % minlen, buf)


def unicode_strings(buf, minlen=4):
    out = []
    for m in re.finditer((rb"(?:[\x20-\x7e]\x00){%d,}" % minlen), buf):
        out.append(m.group().decode("utf-16-le", "replace").encode("ascii", "replace"))
    return out


def ioctl_candidates(buf):
    """Every aligned dword whose low byte encodes a plausible METHOD_* value."""
    hits = {}
    for off in range(0, len(buf) - 4):
        v = struct.unpack_from("<I", buf, off)[0]
        if 0x80000000 <= v <= 0xFFFFFFFF:
            # transfer method in low 2 bits, function >= 0x800, device >= 0x8000
            method = v & 3
            function = (v >> 2) & 0xFFF
            device = (v >> 16) & 0xFFFF
            if method in (0, 1, 2, 3) and 0x800 <= function <= 0xFFF and device >= 0x8000:
                hits.setdefault(v, []).append(off)
    return hits


def report(path):
    buf = open(path, "rb").read()
    lines = ["", "=" * 70,
             "%s  (%d bytes)" % (os.path.basename(path), len(buf)),
             "=" * 70]

    names = sorted({s.decode("ascii", "replace") for s in ascii_strings(buf, 6)})
    dev = [n for n in names if n.startswith("\\") or "Device" in n or "DosDevices" in n]
    lines.append("-- device / link names")
    lines += ["   " + n for n in (dev or ["(none found in ascii)"])]

    wide = sorted({s.decode("ascii", "replace") for s in unicode_strings(buf, 4)})
    wide = [w for w in wide if w.startswith("\\") or "Device" in w]
    lines.append("-- device / link names (utf-16)")
    lines += ["   " + n for n in (wide or ["(none found in utf-16)"])]

    interesting = [n for n in names
                   if re.search(r"\\Device\\|\\DosDevices\\|\\.\\|gdrv|msio|MsIo", n, re.I)]
    lines.append("-- strings mentioning the driver family")
    lines += ["   " + n for n in (interesting or ["(none)"])][:40]

    hits = ioctl_candidates(buf)
    lines.append("-- candidate IOCTL constants (%d distinct)" % len(hits))
    for v in sorted(hits):
        lines.append("   %#010x  at %s" % (v, ", ".join("%#x" % o for o in hits[v][:4])))
    return lines


def main():
    lines = []
    seen = set()
    for name in TARGETS:
        if name in seen:
            continue
        seen.add(name)
        p = os.path.join(DRV, name)
        if not os.path.exists(p):
            lines.append("MISSING %s" % p)
            continue
        lines += report(p)
    text = "\n".join(lines) + "\n"
    open(OUT, "w", encoding="utf-8").write(text)
    sys.stdout.write("wrote %s (%d lines)\n" % (OUT, len(lines)))


main()
