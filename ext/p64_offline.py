r"""p64_offline.py -- run p64_pairs.py end-to-end with no driver and no game.

FakeGio is installed over gio.Gio before p64_pairs.main() grabs it, so p64 runs
its REAL cycle -- seed load, stability snapshots, GO, shot loop, verdict -- on
synthetic physical pages served from a dict.  Scenarios are exact, not
probabilistic; the point is to catch the shot-loop bookkeeping faults (the
IndexError a live run hit right after GO) without booking game time.

Scenarios:
  frag  -- cluster A shield member 100 -> 0 at shot 2, stays down (a frag hit)
  burst -- the same member 100/70/40/0 (a regen fight), only the final hold counts
  fault -- like frag plus B's page faulting from shot 2; its members must go
           None, get skipped, and must not poison A's verdict
  flat  -- nothing moves; VERDICT must be no-cluster
  stale -- a bogus-base seed; SEED100 must read 0/N and p64 must bail rc 3
           before the collect (the 174154 stale-seed FATAL regression)

Usage: python ext\p64_offline.py [all|frag|burst|fault|flat|stale]
Exit 0 = every scenario matched its expectation; 1 = mismatch; 5 = p64 FATAL
(the traceback is written to the scenario's log).  Offline: touches nothing.
"""
import os
import struct
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

ROOT = os.path.dirname(HERE)
F100 = 0x42C80000

A_BASE, B_BASE = 0x6c6af0864, 0x6607b9f78      # the live-verified pair
A_PAGE, B_PAGE = A_BASE & ~0xFFF, B_BASE & ~0xFFF
SHIELD = A_BASE + 0x28                          # the member a frag takes to 0
SEED = os.path.join(ROOT, "temp", "p64_offline_seed.txt")
SEED_TEXT = ("# offline seed (bases from the live p64_seed12 run)\n"
             "0x6c6af0864 0x0,0x28,0x50,0x78\n"
             "0x6607b9f78 0x0,0x40,0x50\n")
STALE = os.path.join(ROOT, "temp", "p64_offline_seed_stale.txt")
STALE_TEXT = ("# bogus bases: nothing lives here -> SEED100 0/N -> bail rc 3\n"
              "0x1234000 0x0,0x178\n"
              "0x9999000 0x0\n")

FLIPS = {                                       # page-pass -> new bits for SHIELD
    "frag": {4: 0x00000000},                    # shot2: 100 -> 0
    "burst": {4: 0x428C0000, 5: 0x42200000, 6: 0x00000000},   # 70, 40, then 0
    "fault": {4: 0x00000000},
    "flat": {},
}
FAULT_PASS = 4                                  # B's page faults from this pass on

EXPECT = {"frag": ("cluster", 100.0), "burst": ("cluster", 40.0),
          "fault": ("cluster", 100.0), "flat": ("no-cluster", None),
          "stale": ("-", None)}

CURRENT = ["frag"]
TB = []


class FakeGio(object):
    """read_phys over a dict; pages not in the map fault.  Scenario via CURRENT."""

    def __init__(self, path=None, chunk=gio.PAGE, map_cache_pages=64):
        self.chunk = chunk
        self.ram_top = 0x780000000
        self.vals = {}
        for ln in SEED_TEXT.splitlines()[1:]:
            pb, po = ln.split()
            for o in po.split(","):
                self.vals[int(pb, 16) + int(o, 16)] = F100
        self.passes = {}
        self.scenario = CURRENT[0]

    def read_phys(self, pa, size):
        page = pa & ~0xFFF
        n = self.passes.get(page, 0) + 1
        self.passes[page] = n
        if self.scenario == "fault" and page == B_PAGE and n >= FAULT_PASS:
            raise OSError(5, "injected fault %#x pass=%d" % (page, n))
        if page == A_PAGE and n in FLIPS[self.scenario]:
            self.vals[SHIELD] = FLIPS[self.scenario][n]
        buf = bytearray(size)
        for a, bits in self.vals.items():
            if (a & ~0xFFF) == page and pa <= a < pa + size:
                struct.pack_into("<I", buf, a - pa, bits)
        return bytes(buf)

    def close(self):
        pass


def fake_factory():
    return FakeGio()


def main(argv):
    with open(SEED, "w") as fh:
        fh.write(SEED_TEXT)
    with open(STALE, "w") as fh:
        fh.write(STALE_TEXT)

    import p64_pairs as P
    base_out = P.Out

    class Out2(base_out):
        def __call__(self, s):
            if s.startswith("FATAL"):
                TB.append(traceback.format_exc())
            base_out.__call__(self, s)

    P.Out = Out2
    gio.Gio = fake_factory                      # p64_pairs.gio is this module

    names = [a for a in argv if not a.startswith("-")] or ["all"]
    if names == ["all"]:
        names = ["frag", "burst", "fault", "flat", "stale"]
    allok = True
    for name in names:
        allok = run_scenario(P, name) and allok
    print("REPRO %s" % ("all-ok" if allok else "failures"))
    return 0 if allok else 1


def run_scenario(P, name):
    rid = time.strftime("%Y%m%d_%H%M%S")
    out_p = os.path.join(ROOT, "temp", "p64_offres_%s_%s.txt" % (name, rid))
    log_p = os.path.join(ROOT, "temp", "p64_off_%s_%s.txt" % (name, rid))
    CURRENT[0] = name
    del TB[:]
    args = ["--seed=" + (STALE if name == "stale" else SEED), "--out=" + out_p, "--wait=0", "--pre=0",
            "--shots=10", "--every=0.05", "--nade2=2",
            "--seed-out=" + os.path.join(ROOT, "temp", "p64_offseed_%s.txt" % name)]
    rc = P.main(args)
    body = ""
    if os.path.exists(out_p):
        with open(out_p, encoding="utf-8") as fh:
            body = fh.read()
    want, drop = EXPECT[name]
    if name == "stale":                        # no verdict: the SEED100 bail fires first
        ok = rc == 3 and "SEED100-FAIL" in body
    else:
        ok = rc in (0, 1) and ("VERDICT %s" % want) in body
    if drop is not None:
        ok = ok and any("CAND " in ln and ("drop=%.1f" % drop) in ln
                        for ln in body.splitlines())
    if name == "fault":
        ok = ok and not any("CAND " in ln and "0x6607b9f78" in ln
                            for ln in body.splitlines())
    if any(ln.startswith("MISMATCH") for ln in body.splitlines()):
        ok = False                              # drift must not happen with fixed ids
    with open(log_p, "w") as fh:
        fh.write("scenario=%s rc=%d expect_verdict=%s expect_drop=%s\n"
                 % (name, rc, want, drop))
        if TB:
            fh.write("TRACEBACK:\n%s\n" % TB[0])
        fh.write("--- p64 out ---\n" + body)
        fh.write("REPRO %s %s\n" % (name, "OK" if ok else "FAIL"))
    print("REPRO %s %s rc=%d log=%s" % (name, "OK" if ok else "FAIL", rc,
                                        os.path.basename(log_p)))
    return ok


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
