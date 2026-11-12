# h392 final evidence: bytes of six FRESH name hits, nothing dereferenced.
import os, struct, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ext"))
import gio, dumplive as dl, qk_va
OUT = os.path.join(os.path.dirname(__file__), "_h392_hits_readback.txt")
def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f: f.write(s + "\n")
open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"' + os.path.abspath(__file__) + '"'))
g = gio.Gio(chunk=0x1000)
ranges, note = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = qk_va.Ram(ranges).page_ok
for h in (0x1860DA5E0, 0x1DB967920, 0x2D87FB490, 0x370C7BFF2,
          0x385F57E0B, 0x63DFF3FF2):
    say("HIT=%#x" % h)
    if not g.is_ram(h & ~0xFFF):
        say("RAM_GUARD")
        continue
    for pa in range(h - 0x500, h + 8, 0x40):
        if not g.is_ram(pa):
            say("guard=%#x" % pa)
            continue
        try:
            p = g.read_phys(pa, 64)
        except OSError as e:
            say("pa=%#x err=%s" % (pa, e))
            continue
        if any(p):
            say("rel=%+#x bytes=%s" % (pa-h, p.hex()))
    # Read each hit containing page independently, no unbounded pointer use.
    # Skip the offset-only display when the name no longer occupies the hit:
    # its moved/recycled bytes are not EPROCESS evidence and were revalidated.
    try:
        live = g.read_phys(h, 15)
        say("fresh_hit_readback=%r hit_still_named=%s" %
            (live, live == b"r5apex_dx12.ex\0"))
    except OSError as e:
        say("fresh_hit_read_error=%s" % e)
say("RESULT: fresh_hit_bytes_read_back")
g.close()