"""dm32_probe.py -- per-class diagnostics: replay one initialiser and show the
sentinel slots ("should_never_see_this") it writes, the records that follow
them, and the registration calls with their resolved arguments.

Usage: python dm32_probe.py DT_Name [more names...]
"""
import struct
import sys

import dm32

SENT = next(v for v, s in dm32.STR.items() if s == "should_never_see_this")
Q = struct.pack("<Q", SENT)
print("sentinel literal at %#x" % SENT)


def rec(img, r):
    return (dm32.rd0(img, r, 4), dm32.rd0(img, r + 4, 4),
            dm32.rd0(img, r + 0xc, 4),
            dm32.python_name(dm32.rd0(img, r + 0x28, 8)))


def sents(img):
    out = []
    for va in sorted(img):
        if all(img.get(va + 0x28 + i) == Q[i] for i in range(8)):
            out.append(va)
    return out


for want in sys.argv[1:]:
    fnva, dts = next((k, v) for k, v in dm32.DT_BY_FUNC.items()
                     if any(n == want for _, _, n in v))
    f = dm32.func_at(fnva)
    flat, stores, calls, nins, rflat = dm32.runs(f)
    print("")
    print("=== %s  init=%#x-%#x  %d insn  %d stores"
          % (want, f[0], f[1], nins, len(stores)))
    for iva, tva, nm in dts:
        print("   lea %#x name=%s  hint=%#x"
              % (iva, nm, (tva + len(nm) + 1 + 15) & ~15))
    for a, args in calls:
        print("   call %#x  rcx=%s rdx=%s r8=%s r9=%s"
              % (a, args.get("rcx"), args.get("rdx"), args.get("r8"),
                 args.get("r9")))
    ss = sents(flat)
    print("   %d sentinel slots in this initialiser" % len(ss))
    for s in ss:
        print("   sentinel %#x  chain:" % s)
        for k in range(1, 9):
            r = s + k * dm32.STRIDE
            t, off, sz, nm = rec(flat, r)
            print("      +%d %#x  t=%#06x off=%#07x sz=%#04x %s"
                  % (k, r, t, off, sz, nm))
