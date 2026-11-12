"""Deterministic qk_live unit tests; never opens the game, driver, or overlay."""
import json
import io
import math
import os
import struct
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import qk_live as L


def matrix(w=1024, h=768):
    m = [0.0] * 16
    m[4], m[9], m[15] = 512.0 / w, 0.005, 1.0
    m[12], m[13] = 0.0, 0.0  # homogeneous NDC offsets, NOT screen-pixel offsets
    m[3], m[10] = -0.0042, 1.0  # X depth, Y screen-X, Z screen-up
    m[2] = 0.01  # small but strictly above the structural row-length minimum
    return m


class GeometryTests(unittest.TestCase):
    def test_utf16_two_lane_decoder_does_not_touch_game_memory(self):
        raw = "kern30120".encode("utf-16-le")
        self.assertEqual("utf16", L.decode_position(raw, (1, 10), "utf16"))
        self.assertEqual("kern30120", raw.decode("utf-16-le"))

    def test_component_layout_and_zero_preservation(self):
        f = [0.0] * 48
        for base in (0, 48):
            fi = base // 4
            f[fi:fi + 3] = [100.0, 0.0, 300.0]
        f[16], f[32], f[16 + 12], f[32 + 12] = 0.0, 300.0, 0.0, 300.0
        f[5 * 4 + 1:5 * 4 + 4] = [1.0, 1.0, 1.0]
        raw = struct.pack("<48f", *f)
        self.assertEqual((100.0, 0.0, 300.0),
                         L.seed_triple(raw, L.COMPONENT_TRIPLE, True))
        self.assertEqual((100.0, 0.0, 300.0), L.seed_triple(raw[:44], (0, 1, 2)))
        bad = bytearray(raw)
        struct.pack_into("<f", bad, 12, 1.0)
        self.assertIsNone(L.seed_triple(bytes(bad), L.COMPONENT_TRIPLE, True))
        self.assertIsNone(L.decode_position(raw, (1, 10), "component3x4", True))

    def test_projection_excludes_offscreen_and_accounts_for_every_record(self):
        m = matrix()
        cases = {"behind": (1000.0, 0.0, 0.0),
                 "invalid": (float("nan"), 50.0, 50.0),
                 "bad_size": (238.0, 0.0, 0.0),
                 "visible": (150.0, 0.0, 0.0),
                 "offscreen": (150.0, 100000.0, 200.0),
                 "bad_head": (237.5, 0.0, -3.3),
                 "clipped": (150.0, 0.0, -80.0)}
        boxes, counts = L.project_entities(m, list(enumerate(cases.values())), 1024, 768)
        self.assertEqual(len(cases), counts["candidates"])
        self.assertEqual(1, counts["behind"])
        self.assertEqual(1, counts["offscreen"])
        self.assertEqual(1, counts["invalid"])
        self.assertEqual(2, counts["visible"])
        self.assertEqual(1, counts["clipped"])
        self.assertEqual(counts["candidates"], counts["visible"] + counts["behind"] +
                         counts["bad_head"] + counts["bad_size"] + counts["offscreen"] +
                         counts["invalid"])
        for x0, y0, x1, y1, depth in boxes:
            self.assertTrue(0 <= x0 < x1 <= 1024)
            self.assertTrue(0 <= y0 < y1 <= 768)
            self.assertTrue(math.isfinite(depth))
        self.assertIsNone(L.project(m, 1000, 0, 0, 1024, 768))
        self.assertIsNone(L.project(m, float("inf"), 0, 0, 1024, 768))

    def test_bad_dimensions_and_structural_matrix_gate(self):
        with self.assertRaises(ValueError):
            L.project_entities(matrix(), [], 1, 1080)
        self.assertFalse(L.matrix_plausible([0.0] * 16))
        self.assertFalse(L.matrix_plausible([1.0] * 15 + [float("nan")]))
        self.assertTrue(L.matrix_plausible(matrix()))


def make_source(path, pid=99, captured=None, verified=True, roles=("remote_player",)):
    records = []
    for i, role in enumerate(roles):
        records.append({"pa": hex(0x2000 + i * 0x100), "position_offsets": [0, 1, 2],
                        "layout": "contiguous", "role": role, "local": role == "local_player"})
    doc = {"version": 1, "pid": pid, "captured_ts": captured or time.time(),
           "layout": "contiguous", "player_validated": verified, "records": records}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f)
    return path


class FakePhysical:
    def __init__(self):
        self.ranges = [(0x1000, 0x100000)]
        self.note = "synthetic RAM interval"
        self.g = SimpleNamespace(ram_top=0x100000)
        self.reads = self.refused = self.failed = 0
        self.fail_position = False
        self.violations = []
        self.closed = False

    def alive(self):
        return 99

    def read(self, pa, size, tries=2):
        self.reads += 1
        if not self.ok(pa, size):
            self.violations.append((pa, size))
            self.refused += 1
            return None
        if pa == 0x1000:
            return struct.pack("<%df" % (size // 4), *matrix(), *([0.0] * 16))
        if 0x2000 <= pa < 0x3000:
            if self.fail_position:
                return None
            f = [0.0] * (size // 4)
            i = (pa - 0x2000) // 0x100
            f[0:3] = [150.0, float(i) * 0.1, 0.0]
            return struct.pack("<%df" % len(f), *f)
        self.failed += 1
        return None

    def ok(self, pa, size):
        return any(lo <= pa and pa + size <= hi for lo, hi in self.ranges)

    def close(self):
        self.closed = True


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.path.join(ROOT, "temp"))
        self.path = os.path.join(self.temp.name, "players.json")

    def tearDown(self):
        self.temp.cleanup()

    def test_legacy_collision_and_unverified_gate(self):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("game_pid=99\n @0x999 (1,2,3)\n SEED 0x2000\n @0x2000 quat\n")
        result = L.read_seed_source(self.path, 99)
        self.assertEqual([0x2000], [r["pa"] for r in result["records"]])
        self.assertEqual("player_type_unverified", result["gate"])
        diagnostic = L.read_seed_source(self.path, 99, allow_unverified=True)
        self.assertEqual("player_type_unverified", diagnostic["gate"])
        self.assertEqual([r["pa"] for r in result["records"]],
                         [r["pa"] for r in diagnostic["records"]])

    def test_independent_pid_staleness_type_and_format_gates(self):
        stamp = time.time()
        make_source(self.path, pid=99, captured=stamp)
        bad_pid = L.read_seed_source(self.path, 98, stamp)
        self.assertEqual("pid_mismatch", bad_pid["gate"])
        self.assertNotIn("age_seconds", bad_pid)
        self.assertEqual("stale", L.read_seed_source(self.path, 99, stamp + 3601)["gate"])
        make_source(self.path, captured=stamp, verified=False)
        self.assertEqual("player_type_unverified", L.read_seed_source(self.path, 99, stamp)["gate"])
        with open(self.path, "w", encoding="utf-8") as f:
            f.write('{"version":999,"records":[]}')
        self.assertEqual("invalid_json", L.read_seed_source(self.path)["gate"])

    def test_zero_cap_keeps_every_remote_and_failed_reads_invalidate(self):
        make_source(self.path, roles=("remote_player", "local_player", "remote_player"))
        transport = FakePhysical()
        with mock.patch.object(L, "Phys", return_value=transport):
            session = L.Session(cap=0, base=0x1000, rva=0, census_path=self.path,
                                refresh_seconds=1000)
            self.assertEqual(2, len(session.prime()))
            self.assertEqual(1, session.local_excluded)
            self.assertEqual([0x2000, 0x2200], [pa for pa, _ in session.ents])
            session.tick(1024, 768)
            self.assertEqual(2, len(session.boxes))
            transport.fail_position = True
            self.assertEqual([], session.tick(1024, 768))
            self.assertEqual([], session.ents)
            transport.violations = []
            self.assertIsNone(transport.read(0x8, 4))  # definitely below the RAM interval
            self.assertIn((0x8, 4), transport.violations)
        rc, verdict = L.live_verdict(session, False, True)
        self.assertIn("SKIPPED", verdict)
        self.assertNotEqual(0, rc)

    def test_world_component_cannot_become_a_player_via_geometry(self):
        make_source(self.path, roles=("world_component",))
        with mock.patch.object(L, "Phys", return_value=FakePhysical()):
            session = L.Session(cap=0, base=0x1000, census_path=self.path)
            self.assertEqual([], session.prime())
            self.assertEqual(1, session.skipped_unverified)
        pending = SimpleNamespace(source={"gate": "player_type_unverified"},
                                  allowed_to_draw=False, ents=[], boxes=[])
        self.assertNotEqual(0, L.live_verdict(pending, True, True)[0])


class ConfigTests(unittest.TestCase):
    def test_sanitization_persistence_and_valid_key_cycles(self):
        cfg = dict(L.DEFAULTS, hz=1000, thick=-10, scheme=-1, esp=103)
        fixed = L.sanitize_config(cfg)
        self.assertEqual(20, fixed["hz"])
        self.assertEqual(1, fixed["thick"])
        self.assertEqual(len(L.SCHEMES) - 1, fixed["scheme"])
        self.assertEqual(1, fixed["esp"])
        with tempfile.TemporaryDirectory(dir=os.path.join(ROOT, "temp")) as d:
            path = os.path.join(d, "config.txt")
            self.assertTrue(L.cfg_save(fixed, path))
            self.assertEqual(fixed, L.cfg_load(path))
        self.assertEqual("off", L.apply_key(dict(L.DEFAULTS, esp=1), "esp")[1])
        self.assertEqual(30, L.apply_key(dict(L.DEFAULTS, hz=20), "hz")[1])


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    text = stream.getvalue() + "\nRESULT: unit-tests=%d failures=%d errors=%d\n" % (
        result.testsRun, len(result.failures), len(result.errors))
    with open(os.path.join(ROOT, "temp", "_qk_live_unit_result.txt"), "w",
              encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(text)
    sys.exit(not result.wasSuccessful())

