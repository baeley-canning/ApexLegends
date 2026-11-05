r"""p72_root.py -- serve a synthetic page-table page over the device read path.

The game's PML4 frame (0x514c3e000) is one of the frames gdrv3 cannot map
(1450 at 4k, at 2M and at 1G granularity, on three different IOCTLs), while
its neighbours read fine.  Only two of its 512 entries are needed: [0] for the
heap half and [255] for the module half, so they are reconstructed bottom-up
and handed to the walker here instead of being read from silicon.

Overlay file (text, one directive per line):

    self 0x514c3e000
    entry 0 0x6c0a42067          # index, value
    entry 255 0x6c0b31067

wrap() returns a proxy: reads inside a supplied page come from the buffer,
everything else goes to the real device, every other attribute is forwarded.
"""
import struct

PAGE = 0x1000


def load(path):
    """-> (pages dict {pa: bytearray}, list of notes) from an overlay file."""
    pages = {}
    notes = []
    with open(path, encoding="utf-8") as f:
        for ln in f:
            ln = ln.split("#", 1)[0].strip()
            if not ln:
                continue
            bits = ln.split()
            if bits[0] == "self" and len(bits) >= 2:
                pa = int(bits[1], 0) & ~0xFFF
                pages.setdefault(pa, bytearray(PAGE))
                notes.append("overlay page %#x" % pa)
            elif bits[0] == "entry" and len(bits) >= 3 and pages:
                idx = int(bits[1], 0)
                val = int(bits[2], 0)
                target = list(pages)[-1]
                if not 0 <= idx < 512:
                    raise ValueError("entry index %d out of range" % idx)
                struct.pack_into("<Q", pages[target], idx * 8, val)
                notes.append("entry[%d] = %#x" % (idx, val))
    if not pages:
        raise ValueError("no self line in %s" % path)
    return pages, notes


class Overlay(object):
    def __init__(self, g, pages):
        object.__setattr__(self, "_g", g)
        object.__setattr__(self, "_pages", pages)

    def read_phys(self, pa, size):
        for base, buf in self._pages.items():
            if base <= pa and pa + size <= base + PAGE:
                off = pa - base
                return bytes(buf[off:off + size])
        return self._g.read_phys(pa, size)

    def __getattr__(self, name):
        return getattr(object.__getattribute__(self, "_g"), name)


def wrap(g, path):
    pages, notes = load(path)
    return Overlay(g, pages), notes
