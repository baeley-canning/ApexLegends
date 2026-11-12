"""mk14: launch-time table-hierarchy snapshotter (transport fork A).

The 1450 law (mk13) kills live page tables minutes after allocation - mk15
measured onset <=131 s for fresh processes.  But between t=0 and onset the
frames read fine.  So: catch the game's PML4 the moment the process appears,
dump the whole hierarchy, and re-dump every 60 s until the onset takes it.

No EPROCESS dependency: fresh page-table frames tonight all landed in high RAM
(20-27 GiB), so this sweeps [16 GiB, ram_top) at 16 KiB granularity (4 KiB
drill on failed pieces) for pages whose kernel half matches the SHARED kernel
PML4 entries (learned from pid 6004's freed, readable PML4).  Live PML4s of
other processes are dead (1450) so only FRESH ones match-and-read; the game's
is tagged by finding r5apex strings among its mapped leaf pages.

Snapshot file per round: _snap_<pid>_r<N>.bin  = repeated
  <Q B 7x> (frame_pa, level 0..3) + 4096 bytes of table content.
Levels: 0=PML4 1=PDPT 2=PD 3=PT.  PS-bit entries (1 GB/2 MB leaves) are
recorded in the sidecar log, not recursed.

Wait mode: --old=<pid> waits until find_pid() reports a pid != old (or any pid
if none).  Read-only, gdrv3 only, R10-guarded, GIO_DST_LAST=1.
"""
import os
import struct
import sys
import time

os.environ["GIO_DST_LAST"] = "1"

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import gio                     # noqa: E402
import dumplive as dl          # noqa: E402

OUT = os.path.join(HERE, "_mk14_out.txt")
PAGE = 0x1000
PIECE = 0x4000
BAND_LO = 0x400000000                      # fresh table frames live high
REF_PML4 = 0x6EF568000                     # freed PML4 of pid 6004 (readable)
ADDR_MASK = 0x000FFFFFFFFFF000
MAX_CAND = 8
ROUNDS = 20
ROUND_GAP = 60.0


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


def kernel_half(buf):
    ent = struct.unpack("<512Q", buf)
    return set(v for v in ent[256:] if v & 1)


def pml4_score(buf, pat):
    ent = struct.unpack("<512Q", buf)
    hits = sum(1 for v in ent[256:] if v in pat and v & 1)
    user = sum(1 for v in ent[:256] if v & 1)
    return hits, user


def dump_hierarchy(g, root, path, in_map):
    pages = {root: 0}
    stats = [0, 0, 0, 0]
    dead = 0
    leaves = set()
    with open(path, "wb") as f:
        todo = [(root, 0)]
        while todo:
            frame, lvl = todo.pop()
            if not in_map(frame):
                say("  frame %#x outside map (R10 skip)" % frame)
                continue
            buf = rd(g, frame)
            if buf is None:
                dead += 1
                continue
            stats[lvl] += 1
            f.write(struct.pack("<QB7x", frame, lvl))
            f.write(buf)
            if lvl == 3:
                continue
            for v in struct.unpack("<512Q", buf):
                if not v & 1:
                    continue
                if lvl in (1, 2) and v & 0x80:      # PS: 1 GB / 2 MB leaf
                    leaves.add(v & ADDR_MASK)
                    continue
                fr = v & ADDR_MASK
                if lvl == 2:
                    leaves.add(fr)
                if fr not in pages and lvl < 3:
                    pages[fr] = lvl + 1
                    todo.append((fr, lvl + 1))
    return stats, dead, leaves


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" %s' % (os.path.abspath(__file__),
                                         " ".join(sys.argv[1:]))))
        return 0
    open(OUT, "w").close()
    say("=== mk14 launch snapshotter %s ===" % time.strftime("%H:%M:%S"))
    old = 0
    for a in sys.argv:
        if a.startswith("--old="):
            old = int(a.split("=", 1)[1])
    g = gio.Gio(chunk=0x10000)
    ranges, note = dl.usable_ranges(g.ram_top, None, None, [])
    say("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))

    def in_map(pa):
        p = pa & ~0xFFF
        return any(a <= p and p + PAGE <= b for a, b in ranges)

    ref = rd(g, REF_PML4)
    if ref is None:
        say("reference PML4 %#x unreadable - cannot build kernel-half "
            "pattern" % REF_PML4)
        say("VERDICT: PARTIAL - reference gone")
        g.close()
        return 1
    pat = kernel_half(ref)
    say("kernel-half pattern: %d shared entries from %#x" % (len(pat),
                                                           REF_PML4))
    # ---- wait for the (new) game process -----------------------------------
    say("waiting for game pid != %d (30 min cap) ..." % old)
    t_wait = time.time()
    pid = None
    while time.time() - t_wait < 1800:
        p = dl.find_pid()
        if p is not None and p != old:
            pid = p
            break
        time.sleep(2)
    if pid is None:
        say("RESULT: no new game process in 30 min")
        say("VERDICT: PARTIAL - never launched (R9)")
        g.close()
        return 3
    t0 = time.time()
    say("GAME pid=%d detected, t=0" % pid)

    # ---- phase 1: PML4-shape content hunt in [BAND_LO, ram_top) ------------
    cands = []
    t1 = time.time()
    for rlo, rhi in ranges:
        lo = max(rlo, BAND_LO)
        if lo >= rhi:
            continue
        pa = lo
        while pa < rhi and len(cands) < MAX_CAND:
            n = min(PIECE, rhi - pa)
            try:
                buf = g.read_phys(pa, n)
                pieces = [(pa + i, buf[i:i + PAGE])
                          for i in range(0, n - (n % PAGE or PAGE) + 1, PAGE)
                          ] if n >= PAGE else []
            except OSError:
                pieces = []
                for q in range(pa, pa + n, PAGE):
                    b = rd(g, q, PAGE, tries=1)
                    if b is not None:
                        pieces.append((q, b))
            for q, b in pieces:
                if len(b) < PAGE:
                    continue
                hits, user = pml4_score(b, pat)
                if hits >= 64:
                    cands.append(q)
                    say("candidate %#012x kernel-hits=%d user-present=%d "
                        "t=%.0fs" % (q, hits, user, time.time() - t0))
            pa += n
    say("sweep done t=%.0fs: %d candidate(s)" % (time.time() - t1,
                                                 len(cands)))
    if not cands:
        say("RESULT: no PML4-shaped readable page in band")
        say("VERDICT: FAIL - shape hunt found nothing; widen band/lower "
            "threshold next")
        g.close()
        return 1

    # ---- phase 2+3: snapshot every candidate, tag the game ------------------
    best = None
    for ci, frame in enumerate(cands):
        path = os.path.join(HERE, "_snap_%d_r0_%x.bin" % (pid, frame))
        stats, dead, leaves = dump_hierarchy(g, frame, path, in_map)
        say("cand%d %#x: pml4/pdpt/pd/pt=%s dead=%d leaves=%d -> %s"
            % (ci, frame, stats, dead, len(leaves),
               os.path.basename(path)))
        # tag: sample leaf pages for game strings
        hits = 0
        sample = sorted(leaves)[::max(1, len(leaves) // 60)][:60]
        for fr in sample:
            b = rd(g, fr, PAGE, tries=3)
            if b and (b"r5apex" in b or b"Respawn" in b):
                hits += 1
        say("cand%d leaf-sample game-string hits=%d/%d"
            % (ci, hits, len(sample)))
        if hits and best is None:
            best = frame
    if best is None:
        best = cands[0]
        say("no candidate string-tagged; defaulting to cand0 %#x" % best)
    say("GAME PML4 = %#x (snapshot r0 complete at t=%.0fs)"
        % (best, time.time() - t0))
    # ---- phase 4: re-dump every 60 s until onset or exit --------------------
    rounds_ok = 1
    onset_at = None
    for r in range(1, ROUNDS + 1):
        time.sleep(ROUND_GAP)
        if dl.find_pid() != pid:
            say("pid %d gone at t=%.0fs - stopping" % (pid,
                                                       time.time() - t0))
            break
        probe = rd(g, best, PAGE, tries=6)
        if probe is None:
            onset_at = time.time() - t0
            say("*** ONSET: game PML4 %#x dead at t=%.0fs (%.1f min) ***"
                % (best, onset_at, onset_at / 60))
            break
        path = os.path.join(HERE, "_snap_%d_r%d_%x.bin" % (pid, r, best))
        stats, dead, leaves = dump_hierarchy(g, best, path, in_map)
        say("round r%d t=%.0fs: levels=%s dead=%d leaves=%d"
            % (r, time.time() - t0, stats, dead, len(leaves)))
        rounds_ok += 1
        if dead:
            say("onset crept into sub-tables at r%d - table growth froze"
                % r)
            break

    say("RESULT: pid=%d pml4=%#x rounds_ok=%d onset=%s"
        % (pid, best, rounds_ok,
           ("%.0fs" % onset_at) if onset_at else "not in window"))
    if rounds_ok >= 1 and onset_at:
        say("VERDICT: PASS - hierarchy snapshotted %d round(s) before the "
            "1450 onset at %.0fs; live tables banked for the session"
            % (rounds_ok, onset_at))
    elif rounds_ok >= 2:
        say("VERDICT: PASS+ - onset did not hit within %d rounds; snapshot "
            "kept pace with table growth" % rounds_ok)
    else:
        say("VERDICT: PARTIAL - snapshot incomplete")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())