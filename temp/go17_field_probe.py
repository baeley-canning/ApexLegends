"""go17 field probe -- M2 synthetic binding proofs; never touches the game.

Covers: spec parse/coerce/refuse, plan union+clusters, decode edges,
read_meta success/refusal-fallback/counters, Session end-to-end binding
(local team provenance, label alignment, --no-fields parity, zero-streak
orthogonality), compose_labels strings.  All reads via FakePhysical.
"""
import json
import os
import struct
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))

import qk_live as L                                              # noqa: E402
from qk_live_regression import FakePhysical, make_source         # noqa: E402

# census-table analogue of the researched netvar set, compressed into one
# 0x30..0x54 window so a synthetic transport serves every cell in one span
FIELDS_COMPACT = [
    {"name": "team", "offset": 0x30, "size": 4, "fmt": "i32"},
    {"name": "hp", "offset": 0x34, "size": 4, "fmt": "i32"},
    {"name": "max_hp", "offset": 0x38, "size": 4, "fmt": "i32"},
    {"name": "life", "offset": 0x40, "size": 1, "fmt": "u8"},
    {"name": "bleed", "offset": 0x41, "size": 1, "fmt": "u8"},
    {"name": "shield", "offset": 0x44, "size": 4, "fmt": "i32"},
    {"name": "temp_shield", "offset": 0x48, "size": 4, "fmt": "i32"},
    {"name": "extra_shield", "offset": 0x4C, "size": 4, "fmt": "i32"},
    {"name": "extra_tier", "offset": 0x50, "size": 4, "fmt": "i32"},
]


def fake_ns(specs=(), plans=None, payloads=None, ranges=None):
    """Minimal read_meta consumer: exactly what read_meta may touch."""
    ph = FakePhysical()
    if ranges:
        ph.ranges = list(ranges)
    ph.payloads = dict(payloads or {})
    return SimpleNamespace(_field_specs=specs, _field_plans=plans or {},
                           no_fields=False, field_reads=0, field_failures=0,
                           field_partial=0, ph=ph)


def specs_of(decls):
    return L.parse_field_specs({"fields": decls})


def plans_of(decls):
    return L.field_plan(specs_of(decls))


def meta_payload(team=2, hp=75, mx=100, life=0, bleed=0,
                 shield=50, temp=25, extra=0, tier=1):
    """Image of the FIELDS_COMPACT window, laid out AT the declared offsets."""
    body = bytearray(0x54 - 0x30)
    for off, fmt, val in ((0x30, "<i", team), (0x34, "<i", hp),
                          (0x38, "<i", mx), (0x40, "<B", life),
                          (0x41, "<B", bleed), (0x44, "<i", shield),
                          (0x48, "<i", temp), (0x4C, "<i", extra),
                          (0x50, "<i", tier)):
        struct.pack_into(fmt, body, off - 0x30, val)
    return bytes(body)


def field_source(path, remote_fields=FIELDS_COMPACT, local_fields="inherit",
                 **kw):
    """make_source(...) plus an optional per-role 'fields' declaration."""
    make_source(path, **kw)
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    for rec in doc["records"]:
        if rec["role"] == "local_player":
            if local_fields == "inherit":
                rec["fields"] = [dict(d) for d in FIELDS_COMPACT]
            elif local_fields is not None:
                rec["fields"] = local_fields
        elif rec["role"] == "remote_player" and remote_fields is not None:
            rec["fields"] = [dict(d) for d in remote_fields]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f)
    return path


class FieldSpecTests(unittest.TestCase):
    def test_happy_path_sorts_offset_and_coerces_scalar_sizes(self):
        rec = {"fields": [
            {"name": "late", "offset": 0x40, "size": 2, "fmt": "i32"},
            {"name": "alpha", "offset": 0x30},
            {"name": "nick", "offset": 0x60, "size": 10, "fmt": "str-u16le"},
            {"name": "alpha", "offset": 0x30, "size": 4}]}
        specs = L.parse_field_specs(rec)
        self.assertEqual(("alpha", 0x30, 4, "i32"),
                         tuple(next(s for s in specs if s[0] == "alpha")))
        self.assertEqual(("late", 0x40, 4, "i32"),
                         tuple(next(s for s in specs if s[0] == "late")))
        self.assertEqual(("nick", 0x60, 10, "str-u16le"),
                         tuple(next(s for s in specs if s[0] == "nick")))
        offs = [s[1] for s in specs]
        self.assertEqual(offs, sorted(offs))

    def test_bad_rows_are_refused_with_one_warning_each(self):
        before = len(L.FIELD_WARNED)
        rec = {"fields": [
            {"name": "neg", "offset": -4, "size": 4},
            {"name": "zero", "offset": 0x10, "size": 0},
            {"name": "weird", "offset": 0x14, "size": 4, "fmt": "f64"},
            {"name": "odds", "offset": 0x18, "size": 3, "fmt": "str-u16le"},
            {"name": "huge", "offset": 0x20, "size": L.META_STR_MAX * 2 + 2,
             "fmt": "str-u16le"},
            {"name": "", "offset": 0x24, "size": 4},
            {"offset": 0x28, "size": 4},
            {"name": "good", "offset": 0x2C, "size": 4}]}
        specs = L.parse_field_specs(rec)
        self.assertEqual([("good", 0x2C, 4, "i32")], list(specs))
        grew = len(L.FIELD_WARNED) - before
        self.assertGreaterEqual(grew, 5)      # every refusal shape warned once
        L.parse_field_specs(rec)              # repeat call warns nothing new
        self.assertEqual(before + grew, len(L.FIELD_WARNED))

    def test_absent_or_malformed_declaration_is_empty_not_fatal(self):
        self.assertEqual((), L.parse_field_specs({}))
        self.assertEqual((), L.parse_field_specs({"fields": "nope"}))
        self.assertEqual((), L.parse_field_specs({"fields": []}))
        self.assertEqual((), L.parse_field_specs(None))
        self.assertEqual((), L.parse_field_specs({"fields": [7, "x", None]}))


class FieldPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compact = specs_of(FIELDS_COMPACT)

    def test_compact_table_gets_single_union_and_single_cluster(self):
        union, clusters = L.field_plan(self.compact)
        self.assertEqual((0x30, 0x54), union)
        self.assertEqual(((0x30, 0x54),), clusters)

    def test_cap_overflow_drops_union_but_keeps_usable_clusters(self):
        union, clusters = L.field_plan(
            self.compact + (("far", 0x9000, 4, "i32"),))
        self.assertIsNone(union)                      # 0x9000-0x30 > the cap
        self.assertEqual(((0x30, 0x54), (0x9000, 0x9004)), clusters)

    def test_small_holes_merge_but_exact_gap_and_empty_behave(self):
        _, clusters = L.field_plan((("a", 0x30, 4, "i32"),
                                    ("b", 0x71, 4, "i32")))  # gap 0x39 < cap
        self.assertEqual(((0x30, 0x75),), clusters)
        _, clusters = L.field_plan((("a", 0x30, 4, "i32"),
                                    ("b", 0x74, 4, "i32")))  # gap == cap: split
        self.assertEqual(((0x30, 0x34), (0x74, 0x78)), clusters)
        self.assertEqual((None, ()), L.field_plan(()))


class FieldDecodeTests(unittest.TestCase):
    def test_scalars_edges_and_shift_semantics(self):
        buf = struct.pack("<iIfB", -7, 0xFFFFFFFF, 3.5, 255)
        self.assertEqual(-7, L.decode_field(buf, ("h", 0, 4, "i32")))
        self.assertEqual(0xFFFFFFFF, L.decode_field(buf, ("u", 4, 4, "u32")))
        self.assertAlmostEqual(3.5, L.decode_field(buf, ("f", 8, 4, "f32")))
        self.assertEqual(255, L.decode_field(buf, ("b", 12, 1, "u8")))
        self.assertIsNone(L.decode_field(buf[:12], ("b", 12, 1, "u8")))
        self.assertIsNone(L.decode_field(buf, ("x", 13, 4, "i32")))
        zz = buf + b"\x00\x00\x00\x00"   # a cluster buffer read at base+4
        self.assertEqual(-7, L.decode_field(zz, ("h", 4, 4, "i32"), shift=-4))
        self.assertIsNone(L.decode_field(buf, ("h", 0, 4, "i32"), shift=-8))

    def test_u16le_string_decode_and_bounds(self):
        raw = "Hero".encode("utf-16-le")
        self.assertEqual("Hero", L.decode_field(raw, ("n", 0, 8, "str-u16le")))
        self.assertIsNone(L.decode_field(raw, ("n", 0, 9, "str-u16le")))
        self.assertIsNone(L.decode_field(raw[:4], ("n", 0, 8, "str-u16le")))


class MetaReadTests(unittest.TestCase):
    BASE = 0x2400

    def _specmap(self, decls):
        s = specs_of(decls)
        u, cl = L.field_plan(s)
        return {self.BASE: s}, {self.BASE: (u, cl)}

    def test_union_success_decodes_everything_and_counts_one_read(self):
        sm, pm = self._specmap([dict(d) for d in FIELDS_COMPACT])
        ns = fake_ns(sm, pm, payloads={self.BASE + 0x30: meta_payload()})
        self.assertEqual({"team": 2, "hp": 75, "max_hp": 100, "life": 0,
                          "bleed": 0, "shield": 50, "temp_shield": 25,
                          "extra_shield": 0, "extra_tier": 1},
                         L.read_meta(ns, self.BASE))
        self.assertEqual(1, ns.field_reads)
        self.assertEqual((0, 0), (ns.field_failures, ns.field_partial))

    def test_union_refusal_repairs_through_both_clusters(self):
        sm, pm = self._specmap([{"name": "hp", "offset": 0x10, "size": 4,
                                 "fmt": "i32"},
                                {"name": "team", "offset": 0x80, "size": 4,
                                 "fmt": "i32"}])
        ns = fake_ns(sm, pm, ranges=[(0x1000, 0x2420), (0x2430, 0x100000)])
        ns.ph.payloads[self.BASE + 0x10] = struct.pack("<i", 0)  # pin hp cell
        ns.ph.payloads[self.BASE + 0x80] = struct.pack("<i", 2)
        self.assertEqual({"hp": 0, "team": 2}, L.read_meta(ns, self.BASE))
        self.assertEqual(3, ns.field_reads)     # refused union + 2 clusters
        self.assertEqual(0, ns.field_partial)   # full recovery, no downgrade

    def test_cell_inside_a_hole_degrades_to_partial(self):
        sm, pm = self._specmap([{"name": "hp", "offset": 0x10, "size": 4,
                                 "fmt": "i32"},
                                {"name": "gapcell", "offset": 0x20, "size": 4,
                                 "fmt": "i32"},
                                {"name": "team", "offset": 0x80, "size": 4,
                                 "fmt": "i32"}])
        ns = fake_ns(sm, pm, ranges=[(0x1000, 0x2420), (0x2430, 0x100000)])
        ns.ph.payloads[self.BASE + 0x80] = struct.pack("<i", 2)
        self.assertEqual({"team": 2}, L.read_meta(ns, self.BASE))
        self.assertEqual(1, ns.field_partial)
        self.assertEqual(3, ns.field_reads)     # union, merged-low cluster, far

    def test_every_attempt_dead_is_one_failure_empty_dict(self):
        sm, pm = self._specmap([{"name": "hp", "offset": 0x10, "size": 4,
                                 "fmt": "i32"}])
        ns = fake_ns(sm, pm, ranges=[(0x1000, 0x2000)])
        self.assertEqual({}, L.read_meta(ns, self.BASE))
        self.assertEqual(1, ns.field_failures)
        self.assertEqual(2, ns.field_reads)     # union then its own cluster

    def test_disabled_or_unknown_pa_costs_nothing(self):
        sm, pm = self._specmap(FIELDS_COMPACT[:2])
        ns = fake_ns(sm, pm)
        ns.no_fields = True
        self.assertIsNone(L.read_meta(ns, self.BASE))
        self.assertEqual(0, ns.field_reads)
        self.assertIsNone(L.read_meta(fake_ns(sm, pm), 0x9999))


class BindEndToEnd(unittest.TestCase):
    ROLES = ("remote_player",) * 3 + ("local_player",)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.path.join(ROOT, "temp"))
        self.path = os.path.join(self.tmp.name, "players.json")

    def tearDown(self):
        self.tmp.cleanup()

    def _session(self, transport, **kw):
        with mock.patch.object(L, "Phys", return_value=transport):
            sess = L.Session(cap=0, base=0x1000, rva=0, census_path=self.path,
                             refresh_seconds=1000, **kw)
            sess.prime()
        return sess

    def _bind_fixture(self):
        tp = FakePhysical()
        tp.payloads[0x2030] = meta_payload()                       # remote: foe
        tp.payloads[0x2130] = meta_payload(team=3, hp=100, mx=100,
                                           shield=0, temp=0)       # mate
        tp.payloads[0x2230] = meta_payload(hp=0, mx=0, team=0, shield=0,
                                           temp=0, extra=0, tier=0)  # all-zero cell
        tp.payloads[0x2330] = meta_payload(team=3)                 # local rec
        field_source(self.path, roles=self.ROLES)
        return tp

    def test_binds_meta_local_team_and_aligns_labels_to_boxes(self):
        sess = self._session(self._bind_fixture())
        self.assertEqual(3, sess.local_team)
        self.assertEqual(1, sess.local_meta_reads)
        sess.tick(1024, 768)
        self.assertEqual({0x2000, 0x2100, 0x2200}, set(sess.meta))
        self.assertEqual([pa for pa, _ in sess.ents], sess.box_pas)
        self.assertEqual(len(sess.labels), len(sess.boxes))
        self.assertEqual(["75/100 | s75t1 | T2", "100", "0 | T0"],
                         sess.labels)
        self.assertIn("fld 3", L.pipeline_summary(sess))

    def test_dead_positions_evict_meta_without_spending_field_reads(self):
        sess = self._session(self._bind_fixture())
        sess.tick(1024, 768)
        self.assertEqual(3, len(sess.meta))
        reads_before = sess.field_reads
        sess.ph.fail_position = True
        sess.tick(1024, 768)
        self.assertEqual({}, sess.meta)              # provenance-loss eviction
        self.assertEqual(reads_before, sess.field_reads)   # zero reads spent
        self.assertEqual(1, sess.zero_streaks[0x2000])   # tick-cadence strike
        self.assertEqual(1, sess.zero_streaks[0x2200])
        self.assertEqual([], sess.ents)                  # corpse pruned same frame
        sess.prime()                                     # corpse converges on prime cadence (M1 doc)
        self.assertEqual(2, sess.zero_streaks[0x2000])   # ledger: M2 never touched it
        self.assertFalse(sess.expired)

    def test_no_fields_runs_the_core_pipeline_bit_identically(self):
        field_source(self.path, roles=self.ROLES)
        with_f = self._session(FakePhysical())
        no_f = self._session(FakePhysical(), no_fields=True)
        self.assertEqual(with_f.prime(), no_f.prime())
        b_with = with_f.tick(1024, 768)
        b_none = no_f.tick(1024, 768)
        self.assertEqual(b_with, b_none)
        self.assertEqual(with_f.ents, no_f.ents)
        self.assertEqual({}, no_f.meta)
        self.assertEqual([], no_f.labels)
        self.assertEqual({}, no_f._field_specs)
        self.assertEqual(0, no_f.field_reads)
        self.assertGreater(with_f.field_reads, 0)
        self.assertIsNone(no_f.local_team)


class RecOverlay(object):
    """Records draw primitives instead of painting a window."""

    def __init__(self):
        self.calls = []

    def fill(self, *a):
        self.calls.append(("fill",) + a)

    def frame(self, *a):
        self.calls.append(("frame",) + a)

    def text(self, x, y, s, color, small=False, width=600):
        self.calls.append(("text", x, y, s))


class RenderGlueTests(unittest.TestCase):
    def test_label_rides_above_the_distance_row(self):
        cfg = dict(L.DEFAULTS, esp=1)
        ov = RecOverlay()
        L.draw_boxes(ov, [(10, 20, 30, 40, 123)], cfg, 0, 0, 0xFFFFFF, 0,
                     labels=["hero 70"])
        texts = [c for c in ov.calls if c[0] == "text"]
        self.assertEqual(2, len(texts))
        self.assertEqual(("text", 10, 0, "123u"), texts[0])
        self.assertEqual(("text", 10, -16, "hero 70"), texts[1])

    def test_missing_or_all_none_labels_change_nothing(self):
        cfg = dict(L.DEFAULTS, esp=1)
        ov_plain, ov_short = RecOverlay(), RecOverlay()
        L.draw_boxes(ov_plain, [(10, 20, 30, 40, 5)], cfg, 0, 0, 1, 0)
        L.draw_boxes(ov_short, [(10, 20, 30, 40, 5)], cfg, 0, 0, 1, 0,
                     labels=[None])
        self.assertEqual(ov_plain.calls, ov_short.calls)


class LabelCompositionTests(unittest.TestCase):
    def test_full_house_ordering_and_formats(self):
        meta = {"hp": 75, "max_hp": 100, "shield": 50, "temp_shield": 25,
                "extra_shield": 0, "extra_tier": 1, "team": 2, "bleed": 1}
        self.assertEqual("75/100 | s75t1 | T2 | DBNO",
                         L.compose_labels({7: meta}, 3)[7])

    def test_dead_names_junk_and_caps(self):
        meta = {"hp": 1, "life": 1, "name": "Ghost\x00tail", "team": 5}
        self.assertEqual("1 | dead | Ghost",
                         L.compose_labels({1: meta}, 5)[1])  # mate: untagged
        out = L.compose_labels({2: {"hp": 0, "name": "n" * 200}}, None)
        self.assertTrue(out[2].startswith("0 | "))
        self.assertLessEqual(len(out[2]), L.LABEL_CHARS_MAX)

    def test_information_free_meta_draws_nothing(self):
        self.assertEqual({}, L.compose_labels({3: {"life": 0}}))
        self.assertEqual({}, L.compose_labels({}, 2))


if __name__ == "__main__":
    import io
    suite = unittest.defaultTestLoader.loadTestsFromModule(
        sys.modules[__name__])
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    text = ("PY %s\n%s\nRESULT: go17-fields=%d failures=%d errors=%d\n"
            % (sys.version.split()[0], stream.getvalue(),
               result.testsRun, len(result.failures), len(result.errors)))
    with open(os.path.join(ROOT, "temp", "_go17_field_result.txt"), "w",
              encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(text)
    sys.exit(not result.wasSuccessful())



