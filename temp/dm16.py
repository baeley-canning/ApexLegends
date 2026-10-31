"""dm16: why did dm13's byte prefilter miss stores we know exist?

For each known (ins_va, dst) stored by dm11, read the bytes around the
instruction, run dm13's STORE_RE over the window and print every est it
produces next to the real destination.
"""
import os
import pickle
import re

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
lines = []


def p(s=""):
    lines.append(s)
    print(s)


with open(os.path.join(HERE, "dm11_cache.pkl"), "rb") as fh:
    C = pickle.load(fh)
secs = C["secs"]
data = open(PATH, "rb").read()


def rd(va, n):
    for nm, sva, vs, rs, rp, ch in secs:
        if sva <= va < sva + max(vs, rs):
            d = va - sva
            return data[rp + d:rp + d + n]
    return b""


MODRM = rb"[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]"
PFX = rb"(?:\x66|\xF3|\xF2|\x48|\x49|\x4C|\x4D|)"
STORE_RE = re.compile(
    rb"(?:" + PFX + rb"\x0F(?:\x11|\x7F)|" + PFX + rb"(?:\x88|\x89|\xC6|\xC7))"
    + MODRM)

PROBES = [(0x14200862C, 0x14E6B0D70), (0x141F0AB78, 0x14E6A5DA8),
          (0x14203CC53, 0x14E6B38C0), (0x1420D912E, 0x14E6D1258),
          (0x141EE7E9F, 0x14E6A5EF0)]
for iva, dst in PROBES:
    raw = rd(iva, 16)
    p("%#x -> dst %#x   bytes %s" % (iva, dst, raw.hex(" ")))
    for m in STORE_RE.finditer(raw):
        est = iva + m.start() + len(m.group(0)) + 4
        p("      match @%+#x len %d est %#x  %s"
          % (m.start(), len(m.group(0)), est, "OK" if est == dst else ""))
    # brute force: which offset o makes start+o give dst directly?
    for o in range(0, 8):
        if est_ok := None:
            pass
        d = dst - (iva + o)
        if -0x80000000 <= d <= 0x7FFFFFFF:
            from struct import pack
            if pack("<i", d) in raw:
                p("      disp for a %d-byte prefix is present at window offset %d"
                  % (o + 3, raw.index(pack("<i", d))))

with open(os.path.join(HERE, "dm16.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
