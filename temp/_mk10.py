# h34w: storm-verify one frame.  Usage: python _mk10.py 0xFRAME [0xCTRL]
# 20 zero-sleep reads on the frame + 20 on ctrl; prints per-read errno and a
# RESULT line.  Read-only; R10 usable-map guard before every read.
import ctypes, sys, time
sys.path.insert(0, r"C:\Users\New User\OneDrive\Desktop\cheating\ext")
import dumplive as dl

OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\_mk10_out.txt"
o = open(OUT, "w")
def say(s):
    o.write(s + "\n"); o.flush()

def storm(g, pa, n=20):
    ok = 0; errs = {}
    t0 = time.perf_counter()
    for _ in range(n):
        try:
            dl.read_phys(g, pa, 0x1000); ok += 1
        except OSError as e:
            errs[e.errno] = errs.get(e.errno, 0) + 1
    ms = (time.perf_counter() - t0) * 1000
    return ok, errs, ms

def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated([r"C:\Users\New User\OneDrive\Desktop\cheating\temp\_mk10.py"] + sys.argv[1:], OUT))
        return
    frame = int(sys.argv[1], 0)
    ctrl = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x436A00000
    g = dl.open_gio()
    if not g:
        say("no gdrv3 handle"); return
    plan = dl.usable_ranges(0, g.ram_top, None)
    ranges = [(a, b) for a, b, _ in plan]
    say("=== mk10 storm %s frame=%#x ctrl=%#x ===" % (time.strftime("%H:%M:%S"), frame, ctrl))
    say("ram_top=%#x ranges=%d" % (g.ram_top, len(ranges)))
    for tag, pa in (("frame", frame), ("ctrl", ctrl)):
        if not any(a <= pa < b for a, b in ranges):
            say("%s %#x NOT in usable map - refused (R10)" % (tag, pa)); continue
        ok, errs, ms = storm(g, pa)
        say("%s %#010x ok=%d/20 errs=%s wall=%.1fms" % (tag, pa, ok, errs, ms))
    say("done")

if __name__ == "__main__":
    main()
