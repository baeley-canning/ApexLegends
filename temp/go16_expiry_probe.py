"""go16 M1.0 probe: zero-signature census expiry.  Synthetic only -- no game,
no driver, no elevation.  Fixtures imported from the canonical regression suite
so the census schema is the real one, never re-typed."""
import importlib.util
import json
import os
import struct
import sys
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import qk_live as L  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "go16_fixtures", os.path.join(ROOT, "temp", "qk_live_regression.py"))
FIX = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(FIX)


class ExpiryTests(unittest.TestCase):
    def setUp(self):
        self.temp = FIX.tempfile.TemporaryDirectory(dir=os.path.join(ROOT, "temp"))
        self.path = os.path.join(self.temp.name, "players.json")

    def tearDown(self):
        self.temp.cleanup()

    def _session(self, transport, **kw):
        kw.setdefault("cap", 0)
        kw.setdefault("base", 0x1000)
        kw.setdefault("rva", 0)
        kw.setdefault("refresh_seconds", 1000)
        kw.setdefault("census_path", self.path)
        with mock.patch.object(L, "Phys", return_value=transport):
            return L.Session(**kw)

    def _zeros(self):
        return struct.pack("<48f", *([0.0] * 48))

    def test_first_void_suppresses_box_but_does_not_retire_yet(self):
        FIX.make_source(self.path, roles=("remote_player", "remote_player"))
        t = FIX.FakePhysical()
        t.payloads[0x2100] = self._zeros()
        s = self._session(t)
        got = s.prime()
        self.assertEqual([0x2000], [pa for pa, _ in got])
        self.assertEqual(1, s.zero_streaks[0x2100])
        self.assertNotIn(0x2100, s.expired)
        self.assertEqual(0, s.expired_events)

    def test_three_strikes_retire_and_stop_spending_reads(self):
        FIX.make_source(self.path, roles=("remote_player", "remote_player"))
        t = FIX.FakePhysical()
        t.payloads[0x2100] = self._zeros()
        s = self._session(t, expiry_zeros=3)
        s.prime(); s.prime()                      # streak reaches 2, still probed
        self.assertNotIn(0x2100, s.expired)
        reads_at_two = t.reads
        s.prime()                                 # third void observation -> retire
        self.assertIn(0x2100, s.expired)
        self.assertEqual(1, s.expired_events)
        self.assertGreater(t.reads, reads_at_two)
        before = t.reads
        s.prime()                                 # retired PA: exactly one live read
        self.assertEqual(1, t.reads - before)
        self.assertEqual([0x2000], [pa for pa, _ in s.ents])

    def test_fresh_signal_resurrects_before_threshold_with_opt_out(self):
        FIX.make_source(self.path, roles=("remote_player", "remote_player"))
        t = FIX.FakePhysical()
        t.payloads[0x2100] = self._zeros()
        s = self._session(t, expiry_zeros=0)      # suppression-only mode
        s.prime(); s.prime()
        self.assertEqual([], [pa for pa, _ in s.ents if pa == 0x2100])
        self.assertNotIn(0x2100, s.expired)
        self.assertEqual(2, s.zero_streaks[0x2100])
        t.payloads[0x2100] = struct.pack("<48f", *(9.0, 7.0, 1.0, *[0.0] * 45))
        s.prime()
        self.assertEqual(0, s.zero_streaks[0x2100])
        self.assertIn(0x2100, [pa for pa, _ in s.ents])
        self.assertEqual(0, s.expired_events)

    def test_generation_reset_clears_expired_set(self):
        FIX.make_source(self.path, roles=("remote_player", "remote_player"))
        t = FIX.FakePhysical()
        t.payloads[0x2100] = self._zeros()
        s = self._session(t, expiry_zeros=1)
        s.prime()                                 # one strike with K=1 retires
        self.assertIn(0x2100, s.expired)
        with open(self.path, encoding="utf-8") as f:
            doc = json.load(f)
        doc["captured_ts"] = doc["captured_ts"] + 5
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        t.payloads[0x2100] = struct.pack("<48f", *(9.0, 7.0, 1.0, *[0.0] * 45))
        s.prime()                                 # new generation: reset + live again
        self.assertEqual(set(), s.expired)
        self.assertEqual([0x2000, 0x2100], [pa for pa, _ in s.ents])
        self.assertEqual(0, s.zero_streaks[0x2000])

    def test_dual_death_flags_round_transition_once(self):
        FIX.make_source(self.path, roles=("remote_player",) * 3)
        t = FIX.FakePhysical()
        t.payloads[0x2000] = self._zeros()
        t.payloads[0x2100] = self._zeros()
        s = self._session(t, expiry_zeros=2)
        s.prime()                                 # 0x2200 survives untouched
        self.assertFalse(s.round_transition)
        s.prime()                                 # both die in the same pass
        self.assertEqual(2, s.expired_events)
        self.assertTrue(s.round_transition)
        self.assertIn("exp 2", L.pipeline_summary(s))
        self.assertIn("ROUND?", L.pipeline_summary(s))
        t.payloads[0x2000] = struct.pack("<48f", *(9.0, 7.0, 1.0, *[0.0] * 45))
        t.payloads[0x2100] = struct.pack("<48f", *(11.0, 5.0, 2.0, *[0.0] * 45))
        s.prime()                                 # survivor anchors healthy>0
        self.assertFalse(s.round_transition)      # quiet pass clears the flag

    def test_tick_prunes_instantly_and_prime_completes_retirement(self):
        """Cadence truth: the tick path prunes a fresh corpse the same frame and
        logs strike 1, but the corpse leaves the per-tick watch (it is off ents);
        retirement converges on the prime cadence (+1 strike per refresh) unless
        the record was alive at prime and died mid-cycle.  Box suppression is
        instantaneous either way; only the LATE counters are cadence-paced."""
        FIX.make_source(self.path, roles=("remote_player", "remote_player"))
        t = FIX.FakePhysical()
        s = self._session(t, expiry_zeros=3)
        s.prime()
        self.assertEqual(2, len(s.ents))          # both alive at prime time
        t.payloads[0x2100] = self._zeros()        # dies right after prime
        s.tick(1024, 768)                         # tick void #1: box gone NOW
        self.assertEqual([0x2000], [pa for pa, _ in s.ents])
        self.assertEqual(1, s.zero_streaks[0x2100])
        self.assertNotIn(0x2100, s.expired)
        s.tick(1024, 768)                         # off ents: no more tick strikes
        self.assertEqual(1, s.zero_streaks[0x2100])
        s.prime(); s.prime()                      # prime cadence supplies #2, #3
        self.assertIn(0x2100, s.expired)
        self.assertEqual(1, s.expired_events)
        self.assertEqual(0, s.zero_streaks[0x2000])  # live neighbour untouched


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    stream = FIX.io.StringIO()
    result = FIX.unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    text = stream.getvalue() + "\nRESULT: go16-expiry=%d failures=%d errors=%d\n" % (
        result.testsRun, len(result.failures), len(result.errors))
    with open(os.path.join(ROOT, "temp", "_go16_expiry_probe.txt"), "w",
              encoding="utf-8") as f:
        f.write(text.replace("\r\n", "\n"))
    print(text[-1600:])
