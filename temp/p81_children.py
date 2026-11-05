r"""p81_children.py -- is the frame a PD (children are tables) or a PT (children are data)?

p78 dumped 0x6c6af0000: 204 present entries, all 4 KiB aligned, PFNs walking
0x143e2c..0x143ed8.  p79/p80 then found 89 present pointers to the frame but
none of their pages passes the 2 MiB-leaf alignment a PD must show, so all of
them are PTs mapping the frame as data -- which decides nothing on its own,
because a frame can be a table in one process and data in another.

What does decide: follow the frame's own entries.  A PD's PS-clear children are
PTs, so they look table-shaped; a PT's children are the data pages it maps, so
they do not.  Both are scored with the same predicate, plus PS-set children are
checked for 2 MiB alignment.

Usage: p81_children.py [--pa=0x...] [--n=12]
Read-only; prints a verdict naming which reading the children support.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

PAGE = 0x1000
OUT = os.path.join(HERE, "_p81_children.txt")
PA = 0x6C6AF000
N = 12


def table_like(g, pa):
    """score a page as a page table: present/software PTE count + sanity."""
    try:
        blk = g.read_phys(pa, PAGE)
    except OSError as e:
        return None, "dead %d" % (e.args[0] if e.args else -1)
    q = struct.unpack_from("<512Q", blk)
    top = g.ram_top
    pres = sum(1 for v in q if v & 1 and 0 < (v & 0x000FFFFFFFFFF000) < top)
    soft = sum(1 for v in q if v & 2 and not v & 1 and v & 0x800)
    ps_al = sum(1 for v in q if v & 1 and v & 0x80 and not v & 0x1FF000)
    ascii_n = sum(1 for c in blk if 0x20 <= c < 0x7F)
    return (pres, soft, ps_al, ascii_n), ""


def main():
    global PA, N
    for a in sys.argv[1:]:
        if a.startswith("--pa="):
            PA = int(a[5:], 0)
        elif a.startswith("--n="):
            N = int(a[3:], 0)
    lines = []

    def log(s):
        lines.append(s)

    log("frame %#x children" % PA)
    g = gio.Gio()
    try:
        blk = g.read_phys(PA, PAGE)
        ents = struct.unpack_from("<512Q", blk)
        pres = [i for i, v in enumerate(ents) if v & 1]
        leaf4k = [i for i in pres if not ents[i] & 0x80]
        leaf2m = [i for i in pres if ents[i] & 0x80]
        log("present=%d  ps-clear=%d  ps-set=%d"
            % (len(pres), len(leaf4k), len(leaf2m)))

        def probe(group, label, n):
            got = ok = ascii_tot = 0
            for i in group[:n]:
                pa = (ents[i] >> 12) << 12
                sc, err = table_like(g, pa)
                log("  %s[%3d] -> %#x %s" % (label, i, pa,
                                             ("dead " + err) if sc is None else
                                             "pres=%d soft=%d ps_al=%d ascii=%d/4096"
                                             % sc))
                if sc is None:
                    continue
                got += 1
                ascii_tot += sc[3]
                if sc[0] >= 40 or sc[1] >= 40:
                    ok += 1
            if not got:
                log("  %s: nothing readable" % label)
                return 0, 0
            log("  %s: table-like %d/%d, mean ascii %d/4096"
                % (label, ok, got, ascii_tot // got))
            return ok, got

        tl_ok, tl_got = probe(leaf4k, "ps-clear", N)
        ps_ok, ps_got = probe(leaf2m, "ps-set", 4)
        al = sum(1 for i in leaf2m[:12] if not ents[i] & 0x1FF000)
        log("ps-set 2MiB-aligned %d of first 12 checked" % al)
    finally:
        g.close()
    if tl_got and tl_ok * 10 >= tl_got * 6:
        log("VERDICT: children are tables -> %#x is a PD" % PA)
    elif tl_got and tl_ok * 10 < tl_got * 4:
        log("VERDICT: children are data -> %#x is a PT (leaf table)" % PA)
    else:
        log("VERDICT: mixed/unclear (table-like %d/%d)" % (tl_ok, tl_got))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
