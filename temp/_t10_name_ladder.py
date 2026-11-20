"""t10: offline unit check of qk_va.resolve_name's deref ladder (no game, no driver).

Why: namePtr (0x10F0, candidate set-B) is deref'ed live for the first time during
today's emit session; these shapes are proven offline so live surprises reduce to
offset truth, not python bugs.  Fixture-only memory; zero device open.

Run:      python temp\\_t10_name_ladder.py
Evidence: temp\\_t10_out.txt   (RESULT: / VERDICT: lines)
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import qk_va                                                     # noqa: E402


class FakeRD(object):
    """Minimal reader stub: addr -> bytes table, call counter, misses = fault."""

    def __init__(self, mem):
        self.mem = dict(mem)
        self.calls = 0

    def read(self, a, n):
        self.calls += 1
        b = self.mem.get(int(a))
        return None if b is None else bytes(b[:n])


def main():
    out_lines = []

    def out(s):
        out_lines.append(str(s))
        print(s)

    P_STR, P_HDR = 0x7FF6ABCD0000, 0x7FF6ABCD1000
    rd = FakeRD({
        P_STR: b"GliwickBot\x00" + bytes(range(1, 47)),
        P_HDR: struct.pack("<Q", P_STR) + bytes(range(200, 240)),
    })
    t, h = qk_va.resolve_name(rd, P_HDR)
    out("indirect: (%r, %s)" % (t, h))
    assert (t, h) == ("GliwickBot", "indirect"), (t, h)

    t, h = qk_va.resolve_name(rd, P_STR)
    out("inline:   (%r, %s)" % (t, h))
    assert (t, h) == ("GliwickBot", "inline"), (t, h)

    t, h = qk_va.resolve_name(rd, 0)
    out("bad-ptr:  (%r, %s)" % (t, h))
    assert (t, h) == (None, "bad-ptr")

    PG = 0x300000000                                    # unmapped in fixture
    t, h = qk_va.resolve_name(rd, PG)
    out("fault:    (%r, %s)" % (t, h))
    assert (t, h) == (None, "unresolved")

    rd.mem[PG] = bytes([1, 2, 3, 4, 255, 254, 253, 252]) + b"\x00" * 40
    t, h = qk_va.resolve_name(rd, PG)
    out("garbage:  (%r, %s)" % (t, h))
    assert h == "unresolved"

    out("RESULT: resolve_name ladder 5/5 shapes as designed reads=%d" % rd.calls)
    out("VERDICT: PASS - offline only; live truth = name_how stats in the emit log")
    with open(os.path.join(HERE, "_t10_out.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(out_lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
