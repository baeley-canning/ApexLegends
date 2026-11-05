r"""p72_rd.py -- read one or more physical pages and print what came back.

Read-only, elevated (device open only).  Exists because "1450 on this PA" has
to be separated from "1450 on this whole region" and from "wrong frame" --
p72's own dumps only show the first fault.

Usage: python ext\p72_rd.py 0x57e88c000,0x57e88b000 [--n=0x1000] [--head=32]
"""
import ctypes
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402


def main(argv):
    pas, n, head = [], 0x1000, 32
    use_map = False
    sweep = 0
    for a in argv:
        if a.startswith("--n="):
            n = int(a[4:], 0)
        elif a.startswith("--head="):
            head = int(a[7:], 0)
        elif a.startswith("--sweep="):
            sweep = int(a[8:], 0)
        elif a == "--map":
            use_map = True
        elif a == "--mapk":
            use_map = "k"
        elif not a.startswith("--"):
            pas += [int(x, 0) for x in a.split(",") if x]
    if sweep and pas:
        # explode into +-sweep pages, the paprobe2 layout
        pas = [pa + i * 0x1000 for pa in pas for i in range(-sweep, sweep + 1)]
    if not pas:
        print("usage: p72_rd.py PA[,PA..] [--n=0x1000] [--head=32] [--map]")
        return 2
    g = gio.Gio(chunk=0x10000)
    try:
        print("ram_top=%#x mode=%s" % (g.ram_top, "map" if use_map else "read"))
        bad = 0
        for pa in pas:
            ok, err, data = False, 0, b""
            if use_map == "k":
                try:
                    o, e, kva = g.map_kernel(pa & ~0xFFF, 0x1000, 0)
                    if not o:
                        raise OSError(e, "map_kernel err")
                    data = ctypes.string_at(kva + (pa & 0xFFF), n)
                    ok = True
                except OSError as e:
                    err = e.errno if e.errno is not None else -1
            elif use_map:
                va = 0
                try:
                    va = g.map_phys(pa & ~0xFFF, 0x1000)
                    data = ctypes.string_at(va + (pa & 0xFFF), n)
                    ok = True
                except OSError as e:
                    err = e.errno if e.errno is not None else -1
                finally:
                    if va:
                        try:
                            g.unmap(va, 0x1000)
                        except OSError:
                            pass
            else:
                try:
                    data = g.read_phys(pa, n)
                    ok = True
                except OSError as e:
                    err = e.errno if e.errno is not None else -1
            if not ok:
                bad += 1
                print("PA %#x n=%#x ram=%s FAULT err=%d"
                      % (pa, n, g.is_ram(pa), err))
                continue
            print("PA %#x n=%#x ram=%s OK %s"
                  % (pa, n, g.is_ram(pa), data[:head].hex()))
        print("RESULT read=%d fault=%d" % (len(pas) - bad, bad))
        return 0 if not bad else 1
    finally:
        g.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
