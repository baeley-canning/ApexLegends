r"""p73_peb.py -- locate the PEB: a field points at a page whose +0x10 is the
module base VA (PEB.ImageBaseAddress).  Read-only, gives (validated) VA+PA.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio

OUT = os.path.join(HERE, "_p73_peb.txt")
PAGE_PA = 0x6c0be0000
EP = 0x6c0be0080
IMGBASE = 0x7FF66ADC0000
PAGE = 0x1000


def main():
    lines = []
    g = gio.Gio()
    try:
        page = g.read_phys(PAGE_PA, PAGE)
        ep_off = EP - PAGE_PA
        hits = 0
        for off in range(ep_off, len(page) - 8, 8):
            q = struct.unpack_from("<Q", page, off)[0]
            if not (0x10000 <= q < 0x800000000000) or q & 7:
                continue
            within = q & 0xFFF
            if within > PAGE - 0x30:
                continue
            try:
                blk = g.read_phys(q & ~0xFFF, PAGE)
            except OSError:
                continue
            base_at10 = struct.unpack_from("<Q", blk, within + 0x10)[0]
            if base_at10 != IMGBASE:
                continue
            head = blk[within:within + 8]
            hits += 1
            lines.append("PEB CAND ep+%#x va=%#x pa=%#x head=%s +0x18=%#x"
                         % (off - ep_off, q, (q & ~0xFFF) + within, head.hex(),
                            struct.unpack_from("<Q", blk, within + 0x18)[0]))
            # corroborate: ProcessParameters at +0x20 must be a canonical VA
            lines.append("   +0x20=%#x +0x38=%#x"
                         % (struct.unpack_from("<Q", blk, within + 0x20)[0],
                            struct.unpack_from("<Q", blk, within + 0x38)[0]))
        lines.append("hits=%d" % hits)
    except Exception:
        import traceback
        lines.append("EXC\n" + traceback.format_exc())
    finally:
        g.close()
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
