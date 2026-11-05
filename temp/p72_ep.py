r"""p72_ep.py -- dump the game EPROCESS page and point at candidate fields.
Read-only.  Looking for SectionBaseAddress (0x7ff.. page-aligned) and Peb
(canonical VA in the < 512 GiB range whose page carries a PEB).
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio

OUT = os.path.join(HERE, "_p72_ep.txt")
PA = 0x6c0be0000          # page holding eprocess 0x6c0be0080
EP = 0x6c0be0080


def canon_user(q):
    return 0x10000 <= q < 0x800000000000 and (q & 7) == 0


def main():
    lines = []
    g = gio.Gio()
    try:
        page = g.read_phys(PA, 0x1000)
        lines.append("dumped %#x %d bytes" % (PA, len(page)))
        ep_off = EP - PA
        for off in range(0, 0x1000, 8):
            q = struct.unpack_from("<Q", page, off)[0]
            if not q:
                continue
            mark = "EP" if off >= ep_off else "  "
            tag = ""
            if canon_user(q):
                tag = "canon"
                if q & 0xFFF == 0 and q >= 0x7F0000000000:
                    tag += " IMGBASE?"
            if off >= ep_off - 0x400 and (tag or off < ep_off + 0x600):
                lines.append("%s %#06x %#018x %s"
                             % (mark, off, q, tag))
        # PEB check: candidate +0x10 == ImageBaseAddress
        for off in range(ep_off, min(ep_off + 0x800, 0x1000 - 8), 8):
            q = struct.unpack_from("<Q", page, off)[0]
            if not canon_user(q):
                continue
            try:
                blk = g.read_phys(q & ~0xFFF, 0x40)
            except OSError as e:
                continue
            img = struct.unpack_from("<Q", blk, q & 0xFFF if (q & 0xFFF) < 0x38
                                     else 0)[0] if (q & 0xFFF) < 0x38 else 0
            sub = struct.unpack_from("<Q", blk, 0x20)[0]
            if sub or img:
                lines.append("PEB? ep+%#x -> %#x  +0x10=%#x +0x20=%#x"
                             % (off - ep_off, q, img, sub))
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
