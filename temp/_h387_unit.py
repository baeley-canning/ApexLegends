"""Fake-only h387 checks. No Gio constructor, game read, write, or DTB."""
import struct
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import _h387_matrix_live as h


class NoDevice:
    def __init__(self, page=None):
        self.calls = []
        self.page = page or {}

    def read_phys(self, pa, size):
        self.calls.append((pa, size))
        return self.page.get(pa)


class FakeImagePE:
    def __init__(self, regions):
        self.regions = regions
        self.size = h.SIZE_OF_IMAGE
        self.stamp = h.STAMP

    def raw(self, rva, size):
        for start, data in self.regions.items():
            if start <= rva and rva + size <= start + len(data):
                return data[rva - start:rva - start + size]
        return None

    def __getitem__(self, item):
        return self.raw(item.start, item.stop - item.start)


def file_layout_fixture():
    pref = 0x140000000
    code = bytearray(0x2000)
    code[:3] = b"\x4c\x8b\xdc"
    pos = 8
    code[pos:pos + 3] = b"\x48\x8d\x05"
    struct.pack_into("<i", code, pos + 3, 0x3D86100 - h.ACCESSOR_RVA - pos - 7)
    code[pos + 7] = 0xC3
    vt = bytearray(0x90)
    fn0, fnm = pref + 0x20EE00, pref + 0x20DB0BE
    struct.pack_into("<Q", vt, 0, fn0)
    struct.pack_into("<Q", vt, 0x80, fnm)
    body = bytearray(0x1000)
    body[:7] = b"\x48\x0f\xbe\x85" + struct.pack("<I", 0x1308)
    body[16:24] = b"\x48\x8b\x84\xc1\x90\xa3\x11\x00"
    body[40:48] = b"\x48\x8b\x84\xc1\x98\xa3\x11\x00"
    return FakeImagePE({
        h.ACCESSOR_RVA: bytes(code),
        0x3D86100: struct.pack("<Q", pref + h.VT_RVA),
        h.VT_RVA: bytes(vt), 0x20DB0BE: bytes(body),
    })


class NoWrites:
    def __init__(self):
        self.lines = []
        self.rc = 2

    def log(self, text=""):
        self.lines.append(text)

    def progress(self, text):
        pass


class H387Tests(unittest.TestCase):
    def test_decode_actual_movsx_opcode_and_object_vtable(self):
        a = h.build_accessor(file_layout_fixture())
        self.assertEqual(a["object"], 0x3D86100)
        self.assertEqual(a["vt"], h.VT_RVA)
        self.assertEqual(a["index"], 0x1308)
        self.assertEqual(a["slots"], h.EXPECTED_SLOTS)

    def test_malformed_file_and_build_are_blocked_without_device(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "bad.exe"
            p.write_bytes(b"MZ")
            with self.assertRaises(h.Blocked):
                h.PE(p)

    def test_physical_interval_boundaries_and_faults(self):
        expected = b"\x5a" * 64
        g = NoDevice({0x300000 - 64: expected})
        pr = h.ExplicitPhysical(g, [(0x100000, 0x300000)])
        self.assertEqual(pr.read(0x300000 - 64, 64), expected)
        for pa, size in [(0x100000 - 1, 1), (0x300000 - 63, 64),
                         (0x300000, 1), (0x300, 1), (0, 8)]:
            self.assertIsNone(pr.read(pa, size))
        self.assertEqual(g.calls, [(0x300000 - 64, 64)])
        self.assertEqual(pr.refused, 5)
        self.assertEqual(pr.read(0x1000, 8), None)

    def test_anchor_relocated_vtable_and_bad_footer(self):
        base = 0x1000000
        a = {"object": 0x100, "vt": 0x1200, "file_vt": 0x140003000,
             "functions": (0x140003000, 0x140004000), "accessor_bytes": b"0123456789abcdef"}
        pe = SimpleNamespace(stamp=h.STAMP, size=h.SIZE_OF_IMAGE)
        g = NoDevice()
        pr = h.ExplicitPhysical(g, [(base, base + h.SIZE_OF_IMAGE)])
        hdr = bytearray(0x400)
        hdr[:2] = b"MZ"
        struct.pack_into("<I", hdr, 0x3C, 0xF8)
        hdr[0xF8:0xFC] = b"PE\0\0"
        struct.pack_into("<I", hdr, 0xF8 + 8, h.STAMP)
        struct.pack_into("<I", hdr, 0xF8 + 0x50, h.SIZE_OF_IMAGE)
        g.page[base] = bytes(hdr)
        g.page[base + h.ACCESSOR_RVA] = a["accessor_bytes"]
        slide = 0x7FF0000
        g.page[base + a["object"]] = struct.pack("<Q", 0x140001200 + slide)
        g.page[base + a["vt"]] = struct.pack("<Q", a["functions"][0] + slide)
        g.page[base + a["vt"] + 0x80] = struct.pack("<Q", a["functions"][1] + slide)
        ev = NoWrites()
        self.assertEqual(pr.validate_layout(base, pe, a, ev), (0x7FF0000 + 0x140000000, slide))
        g.page[base + a["vt"] + 0x80] = struct.pack("<Q", 0)
        with self.assertRaises(h.Blocked):
            pr.validate_layout(base, pe, a, ev)

    def test_readable_none_is_still_not_a_matrix(self):
        pr = h.ExplicitPhysical(NoDevice(), [(0x1000, 0x300000)])
        a = {"object": 0x100, "slots": (0x200, 0x208), "index": 0x1308, "vt": 0x200}
        base, va = 0x1000, 0x10000
        names = (("obj", a["object"], 0x10), ("slots", a["slots"][0], 0x10),
                 ("index", a["index"], 1), ("buf_a", h.EXPECTED_BUFFERS[0], 0x40),
                 ("buf_b", h.EXPECTED_BUFFERS[1], 0x40))
        for name, off, size in names:
            pr.g.page[base + off] = bytearray(size)
        struct.pack_into("<Q", pr.g.page[base + a["object"]], 0, va + a["vt"])
        struct.pack_into("<2Q", pr.g.page[base + a["slots"][0]], 0,
                         va + h.EXPECTED_BUFFERS[0], va + h.EXPECTED_BUFFERS[1])
        ev = NoWrites()
        self.assertFalse(h.gate_accessor(pr, base, va, a, ev))
        self.assertIn("G4_matrix_shape=FAIL", ev.lines)
        self.assertIn("G5_column_projection=SKIPPED (matrix layout/accessor needs binding verification)", ev.lines)
        text = "\n".join(ev.lines)
        self.assertNotIn("VERDICT: PASS", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
