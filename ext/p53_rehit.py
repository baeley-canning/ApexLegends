"""p53_rehit.py -- re-read the class hits now and show bytes around them.

The padump window run showed all-zero rows exactly at the hit offsets
(0x7abc3d800..0xa40) while the sweep had found needles there seconds earlier.
That is either a stale page (PTE changed between scan and dump) or a hit
mapping bug.  This reads the *hit PA itself* right now, 64 bytes before and
192 after, and marks the hit byte -- read-only, so it cannot shift state.

Usage: p53_rehit.py [--rows=N] [--out=path]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

CLASS = os.path.join(os.path.dirname(HERE), "_ritual", "p53_class.txt")
OUT = os.path.join(os.path.dirname(HERE), "temp", "p53_rehit.txt")
BEFORE = 64
AFTER = 192
PAGE = 0x1000


def load_hits(path, rows):
    hits = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("page=") and " pa=" in line:
                pas = line.split(" pa=")[1].split(" ")[0]
                for p in pas.split(","):
                    hits.append(int(p, 16))
    return hits[:rows]


def rows_for(base, data, hit, first, last):
    out = []
    for off in range(first, last, 16):
        chunk = data[off:off + 16]
        if not chunk:
            break
        cells = []
        star = False
        for i, b in enumerate(chunk):
            a = base + off + i
            if a == hit:
                cells.append("<%02x" % b)
                star = True
            else:
                cells.append(" %02x" % b)
        asc = "".join(chr(b) if 0x20 <= b <= 0x7E else "." for b in chunk)
        out.append("    %06x %s |%s|%s" % (off, "".join(cells), asc,
                                           "  *" if star else ""))
    return out


def main(argv):
    rows = 6
    out_path = OUT
    pas = []
    for a in argv:
        if a.startswith("--rows="):
            rows = int(a[7:])
        elif a.startswith("--out="):
            out_path = a[6:]
        elif a.startswith("--pa="):
            pas = [int(x, 16) for x in a[5:].split(",") if x]
    hits = pas[:rows] if pas else load_hits(CLASS, rows)
    log = ["# p53_rehit hits=%d" % len(hits)]
    g = gio.Gio()
    for hit in hits:
        base = hit & ~0xFFF
        first = max(0, (hit & 0xFFF) - BEFORE)
        last = min(PAGE, (hit & 0xFFF) + AFTER)
        try:
            data = g.read_phys_checked(base, PAGE)
        except OSError as e:
            log.append("hit=%#x ERR %s" % (hit, e))
            continue
        blk = data[(hit & 0xFFF):(hit & 0xFFF) + 4]
        u32 = struct.unpack_from("<I", data, first)[0] if first + 4 <= PAGE else 0
        log.append("hit=%#x bytes=%s first_u32=%#010x" % (hit, blk.hex(), u32))
        log.extend(rows_for(base, data, hit, first, last))
    g.close()
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")
    print("\n".join(log))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
