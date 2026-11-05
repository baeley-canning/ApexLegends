"""paprobe3.py -- turn the decoys' flink into a physical address and read the
neighbour EPROCESS.

The three decoy blocks all carry flink 0xffffa401b25a5258, a KERNEL VA.  The
0xffffa40x range is the linear system-VA mapping (a contiguous view of
physical memory), so the neighbour is at PA = VA - base for the region base.
Two bases are tried; at each the bytes are checked for a ProcessObject header,
pid and name at both link lanes.  If it lands, the real ActiveProcessLinks
chain is reachable from there instead of from a stale frame.
READ-ONLY.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

OUT = os.path.join(os.path.dirname(HERE), "_ritual", "p44c_va.txt")
FLINK = 0xFFFFA401B25A5258
BASES = [0xFFFFA40100000000, 0xFFFFA40000000000]
LOG = []


def log(s):
    LOG.append(s)
    print(s)


def probe(g, pa, lane):
    try:
        p = g.read_phys(pa & ~0xFFF, 0x2000)
    except OSError as e:
        log("  pa=%#x lane=%#x ERR %s" % (pa, lane, e))
        return
    b = pa & 0xFFF
    log("  pa=%#x lane=%#x type=%d pid@1d0=%#x name=%r"
        % (pa, lane, p[b], struct.unpack_from("<I", p, b + 0x1D0)[0],
           p[b + 0x338:b + 0x338 + 16].rstrip(b"\x00")))


g = gio.Gio(chunk=0x10000)
for base in BASES:
    pa = FLINK - base
    log("base=%#x -> pa=%#x is_ram=%s" % (base, pa, g.is_ram(pa)))
    if not g.is_ram(pa):
        continue
    for lane in (0x1D8, 0x258):
        probe(g, pa - lane, lane)
g.close()
open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
print("VERDICT: PAPROBE3_DONE")
