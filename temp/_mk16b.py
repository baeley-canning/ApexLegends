"""mk16b: mk16 hardened - mk16 died silently right after finding candidate
0x5336ED000 (0-byte snapshot, no traceback, both parent and child gone).

Hardening:
  - faulthandler to _mk16b_fault.txt (catches AVs/fatals, not just exceptions);
  - whole-main try/except -> traceback into _mk16b_out.txt;
  - unbuffered snapshot writes (evidence preserved on sudden death);
  - dump progress line every 400 pages (liveness);
  - todo/seen caps (false-positive PML4 explosion guard);
  - seeds the candidate set with 0x5336ED000 so a flicker-closed frame from
    mk16's pass is probed directly instead of re-waited for.
Read-only, gdrv3 only, R10-guarded, GIO_DST_LAST=1.
"""
import os
import struct
import sys
import time

import numpy as np

os.environ["GIO_DST_LAST"] = "1"

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import gio                     # noqa: E402
import dumplive as dl          # noqa: E402

OUT = os.path.join(HERE, "_mk16b_out.txt")
FAULT = os.path.join(HERE, "_mk16b_fault.txt")
SEED_CAND = 0x5336ED000                  # mk16's lost candidate
PAGE = 0x1000
PIECE = 0x4000
REF_PML4 = 0x5732E3000                     # freed PML4 of pid 26496 (readable)
ADDR_MASK = 0x000FFFFFFFFFF000
MAX_CAND = 8
PASSES = 40
PASS_GAP = 90.0


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def rd(g, pa, n=PAGE, tries=12):
    for _ in range(tries):
        try:
            return g.read_phys(pa, n)
        except OSError:
            pass
    return None


def score_pages(buf, pat):
    """-> per-4 KiB-page kernel-half hit counts for one piece."""
    arr = np.frombuffer(buf, dtype="<u8").reshape(-1, 512)
    half = arr[:, 256:]
    pres = (half & 1) != 0
    return (np.isin(half, pat) & pres).sum(axis=1)


def dump_hierarchy(g, root, path, in_map):
    stats = [0, 0, 0, 0]
    dead = 0
    leaves = set()
    seen = {root}
    with open(path, "wb", buffering=0) as f:
        todo = [(root, 0)]
        while todo:
            if len(seen) > 300000:
                say("  dump ABORT: seen>300k (false-positive PML4?)")
                break
            frame, lvl = todo.pop()
            frame = int(frame)                      # numpy int64 poison guard
            if not in_map(frame):
                continue
            buf = rd(g, frame)
            if buf is None:
                dead += 1
                continue
            stats[lvl] += 1
            if sum(stats) % 400 == 0:
                say("  dump progress: %d pages (todo=%d)" % (sum(stats),
                                                             len(todo)))
            f.write(struct.pack("<QB7x", frame, lvl))
            f.write(buf)
            for v in struct.unpack("<512Q", buf):
                if not v & 1:
                    continue
                fr = v & ADDR_MASK
                if lvl in (1, 2) and v & 0x80:      # PS: 1 GB / 2 MB leaf
                    leaves.add(fr)
                    continue
                if lvl == 3:
                    leaves.add(fr)                  # data page
                    continue
                if fr not in seen:
                    seen.add(fr)
                    todo.append((fr, lvl + 1))
    return stats, dead, leaves


def tag_game(g, leaves, in_map):
    hits = 0
    sample = sorted(leaves)[::max(1, len(leaves) // 60)][:60]
    for fr in sample:
        if not in_map(fr):
            continue
        b = rd(g, fr, PAGE, tries=3)
        if b and (b"r5apex" in b or b"Respawn" in b or b"EasyAntiCheat" in b):
            hits += 1
    return hits, len(sample)

def sweep(g, plan, pat, in_map, seen):
    """One pass over `plan`; returns new PML4 candidates (frames)."""
    out = []
    for rlo, rhi in plan:
        pa = rlo
        while pa < rhi and len(out) + len(seen) < MAX_CAND * 4:
            n = min(PIECE, rhi - pa)
            try:
                buf = g.read_phys(pa, n)
            except OSError:
                buf = None
            if buf is not None and len(buf) >= PAGE:
                hits = score_pages(buf[:len(buf) // PAGE * PAGE], pat)
                for i in np.nonzero(hits >= 64)[0]:
                    fr = pa + int(i) * PAGE
                    if fr not in seen:
                        out.append(fr)
                        seen.add(fr)
            else:
                for q in range(pa, pa + n, PAGE):
                    b = rd(g, q, PAGE, tries=1)
                    if b is None:
                        continue
                    if score_pages(b, pat)[0] >= 64 and q not in seen:
                        out.append(q)
                        seen.add(q)
            pa += n
    return out


def snapshot(g, frame, tag, pass_n, in_map):
    path = os.path.join(HERE, "_snap_%s_p%d_%x.bin" % (tag, pass_n, frame))
    stats, dead, leaves = dump_hierarchy(g, frame, path, in_map)
    hits, nsamp = tag_game(g, leaves, in_map)
    say("cand %#x p%d: levels=%s dead=%d leaves=%d gamestr=%d/%d -> %s"
        % (frame, pass_n, stats, dead, len(leaves), hits, nsamp,
           os.path.basename(path)))
    return stats, dead, hits


def main():
    import faulthandler
    _fh = open(FAULT, "w", encoding="utf-8")
    faulthandler.enable(_fh)
    try:
        import traceback
        return _main()
    except SystemExit:
        raise
    except Exception:
        import traceback
        say("FATAL EXCEPTION:\n" + traceback.format_exc())
        return 1


def _main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" %s' % (os.path.abspath(__file__),
                                         " ".join(sys.argv[1:]))))
        return 0
    open(OUT, "w").close()
    say("=== mk16 flicker-catcher %s ===" % time.strftime("%H:%M:%S"))
    g = gio.Gio(chunk=0x10000)
    ranges, note = dl.usable_ranges(g.ram_top, None, None, [])
    say("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))

    def in_map(pa):
        p = pa & ~0xFFF
        return any(a <= p and p + PAGE <= b for a, b in ranges)

    ref = rd(g, REF_PML4)
    if ref is None:
        say("VERDICT: PARTIAL - reference PML4 %#x unreadable" % REF_PML4)
        g.close()
        return 1
    ent = struct.unpack("<512Q", ref)
    pat = np.array([v for v in ent[256:] if v & 1], dtype="<u8")
    say("kernel-half pattern: %d entries" % len(pat))

    band = [(max(a, 0x500000000), min(b, 0x700000000))
            for a, b in ranges if b > 0x500000000 and a < 0x700000000]
    low = [(a, min(b, 0x500000000)) for a, b in ranges if a < 0x500000000]
    high = [(max(a, 0x700000000), b) for a, b in ranges if b > 0x700000000]
    band = [r for r in band if r[1] > r[0]]
    low = [r for r in low if r[1] > r[0]]
    high = [r for r in high if r[1] > r[0]]
    plan0 = band + high
    plan_full = plan0 + low

    seen = {SEED_CAND}
    game_frame = None
    t0 = time.time()
    # probe mk16's lost candidate directly before looping
    if rd(g, SEED_CAND, PAGE, tries=6) is not None:
        say("seed candidate %#x READS - snapshotting now" % SEED_CAND)
        stats, dead, hits = snapshot(g, SEED_CAND, "seed", 0, in_map)
        if hits:
            game_frame = SEED_CAND
    else:
        say("seed candidate %#x currently dead - loop will re-catch" %
            SEED_CAND)
    for p in range(PASSES):
        if game_frame is not None:
            break
        tp = time.time()
        plan = plan0 if p < 3 else plan_full
        cands = sweep(g, plan, pat, in_map, seen)
        for fr in cands:
            say("candidate %#012x (pass %d, t=%.0fs)"
                % (fr, p, time.time() - t0))
            stats, dead, hits = snapshot(g, fr, "g%d" % p, p, in_map)
            if hits:
                game_frame = fr
        say("pass %d done in %.0fs: %d new candidate(s)"
            % (p, time.time() - tp, len(cands)))
        time.sleep(PASS_GAP)
    if game_frame is None:
        say("RESULT: %d passes, no game-tagged PML4 ever readable" % PASSES)
        say("VERDICT: FAIL - no flicker window caught; dead-instance walk "
            "at game exit is the fallback (fork B)")
        g.close()
        return 1
    # ---- game tagged: keep re-dumping until onset takes the PML4 ------------
    say("GAME PML4 = %#x (tagged at t=%.0fs) - entering round dumps"
        % (game_frame, time.time() - t0))
    rounds_ok = 0
    onset_at = None
    for r in range(1, 21):
        time.sleep(60.0)
        probe = rd(g, game_frame, PAGE, tries=6)
        if probe is None:
            onset_at = time.time() - t0
            say("*** ONSET: game PML4 dead at t=%.0fs (%.1f min) ***"
                % (onset_at, onset_at / 60))
            break
        stats, dead, leaves = dump_hierarchy(
            g, game_frame,
            os.path.join(HERE, "_snap_game_r%d_%x.bin" % (r, game_frame)),
            in_map)
        say("round r%d t=%.0fs: levels=%s dead=%d leaves=%d"
            % (r, time.time() - t0, stats, dead, len(leaves)))
        rounds_ok += 1
        if dead:
            break
    say("RESULT: game_pml4=%#x rounds_ok=%d onset=%s"
        % (game_frame, rounds_ok,
           ("%.0fs" % onset_at) if onset_at else "not in window"))
    say("VERDICT: PASS - hierarchy banked (rounds=%d); session has live "
        "tables" % rounds_ok)
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())