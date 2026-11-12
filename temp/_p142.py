r"""_p142.py -- who owns this component? pointer scan resolved through the game's CR3.

Seeds are PHYSICAL, so an owner cannot be found by comparing raw addresses.  And
`0xC350280C` (gio.translate) resolves in the CALLING process's context, which does not map
Apex's heap - 187/187 translates failed that way (p142 v1, `temp\_p142_out.txt`).

So resolve through the game's own page tables: take its DTB (name sweep -> `candidates_for`,
the dumplive recipe), build a `Walk`, and `page_pa()` every pointer-looking qword around the
component.  Keep the ones whose frame is within `--near` of the component: those are references
INTO this heap region.  A component array (`TArray<UActorComponent*>`) is a run of consecutive
pointers resolving into the same frame, so runs of >=3 are the find, a lone pointer is a
candidate owner field.

v3: the same pass that hunts the DTB ALSO runs the `_p140.root` shape test, so one sweep
yields the CR3 *and* live seeds (a match boundary zeroes the pools - p135/p139 - so a seed
older than the match is worthless).  The DTB is cached to temp\_dtb.txt for the rest of the
boot/match.  Seeds are ranked by 64 KB density (that is the entity array, not a stray bone).
v4: the DTB hunt keys on the `Proc` pool tag + EPROCESS+0x28 + the LIVE pid at +0x440 - the
image-name hits are largely string copies and the one real EPROCESS on 11/08 belonged to a
dead instance (`temp\_p142c_out.txt`).

Read-only, gdrv3, 12-try immediate retry.  Writes temp\_p142_out.txt (v3 rewrites the file).
Usage: _p142.py [--sweep] [--use-cache] [--at=0x<component>] [--span=0x1800]
                 [--near=0x200000] [--cap=400]
"""
import os
import sys
import threading
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p142_out.txt")
CACHE = os.path.join(HERE, "_dtb.txt")
SEED = 0x5c3230c5c
CODE_LO, CODE_HI = 0x10000, 0x7FFFFFFEFFFF
NEARF = 0.002          # p140/p141 duplicate tolerance (0.2 %)
# EPROCESS field offsets, (image-name, DirectoryTableBase).  11/08 boot: the object at
# 0x2aa1d5010 carries Type=3 @+0x70, name @+0x3a8, pid @+0x240, self-KVA @+0x248 and the
# frame @+0x98 (temp\_p20612_dump_out.txt); +0x338/+0x28 is the pair older notes used, and
# every field is 0x70 higher than that older map, so both are tried.
LAYOUTS = ((0x3a8, 0x98), (0x338, 0x28))
CAL_OK = []            # frames that both read and self-reference on a --cal pass


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def rd(g, pa, n, secs=5.0):
    box = {}

    def work():
        for k in range(12):
            try:
                box["b"] = g.read_phys(pa, n)
                return
            except OSError as e:
                box["e"] = repr(e)
                if k == 5:
                    time.sleep(0.002)

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(secs)
    if t.is_alive():
        return None, "wedge"
    if "b" not in box:
        return None, box.get("e", "no-attempt")
    return box["b"], None


def seeds_from(b, pa, seeds, cap=600):
    """Vectorised `_p140.root` -> record-head PAs (self-validated, no second record needed).

    Layout (p135 hex dump): +0x00 (x,r,r,0) +0x10 (y,0,0,s) +0x20 (z,?,?,0) +0x30 (x,r,r,0)
    +0x40 (y,0,0,s) +0x50 (z,1,1,1) - so zeros are only at lanes 3/5/6/11 and the terminator
    sits at 21..23 with the transform's own copy compared at 12/16/20.  The `1 1 1` run is the
    cheap chunk gate; seeded addresses are PHYSICAL.
    """
    v = np.frombuffer(b, "<f4")
    n = len(v)
    if n < 64:
        return
    on = v == 1.0
    if not (on[:-2] & on[1:-1] & on[2:]).any():
        return
    L = n - 23
    zq = v == 0.0
    av = np.abs(v)
    fin = np.isfinite(v) & (av < 12000.0)
    ok = fin[0:L] & fin[4:L + 4] & fin[8:L + 8]
    for k in (3, 5, 6, 11):
        ok &= zq[k:k + L]
    ok &= on[21:21 + L] & on[22:22 + L] & on[23:23 + L]
    x, y, z = v[0:L], v[4:L + 4], v[8:L + 8]
    dx, dy, dz = v[12:12 + L], v[16:16 + L], v[20:20 + L]
    ok &= np.isfinite(dx) & np.isfinite(dy) & np.isfinite(dz)
    for a, d in ((x, dx), (y, dy), (z, dz)):
        ok &= np.abs(a - d) <= np.maximum(2.0, NEARF * np.maximum(np.abs(a), np.abs(d)))
    ok &= (np.abs(x) > 250.0) | (np.abs(z) > 250.0)
    for i in np.nonzero(ok)[0]:
        if len(seeds) >= cap:
            return
        seeds.append(pa + int(i) * 4)


def find_dtb(g, pid, budget=540.0, seeds=None, proctag=True, frm=0, to=None, cal=False):
    """-> (DTB, seeds).  Two modes:

    * proctag (default): every `Proc` pool tag, then EPROCESS+0x28 (DirectoryTableBase) and
      +0x440 (UniqueProcessId) checked against the LIVE pid.  Image-name hits are a trap: the
      sweep's only candidate on 11/08 was a stale EPROCESS of a dead Apex (pid 69149) whose
      page tables had been freed, so its PML4 refused every read (temp\\_p142c_out.txt).
    * name: the old dumplive recipe, `candidates_for` gated.  Keeps whole-process sweeps fast
      but cannot tell a corpse from the live process.

    The 1 MB chunk carries the same immediate re-try policy as p134; a chunk that still fails
    after 12 instant attempts is skipped, not retried at 4 KB.  Progress every 4 GB.
    """
    if seeds is None:
        seeds = []
    ranges, note = dl.usable_ranges(g.ram_top, 0x1000, None)
    say("ranges=%d note=%s mode=%s" % (len(ranges), note, "proctag" if proctag else "name"))
    hits, procs, calo, t0, chunk, swept, stop = [], [], [], time.time(), 0x100000, 0, False
    del CAL_OK[:]
    seen_all = 0
    for lo, hi in ranges:
        if stop:
            break
        lo = max(lo, frm)
        if to is not None:
            hi = min(hi, to)
        if hi <= lo:
            continue
        pa = (lo + 7) & ~7
        while pa + chunk <= hi:
            if time.time() - t0 > budget:
                say("  scan budget out at %#x" % pa)
                stop = True
                break
            b, _e = rd(g, pa, chunk)
            if b:
                if proctag:
                    i, seen = b.find(b"Proc"), 0
                    while i >= 0 and seen < 60:
                        # _POOL_HEADER is 0x10 bytes on x64 and the tag sits at obj-0xC, so the
                        # object base is resolved from the structure (name string + frame-form
                        # DTB) instead of assumed - an 8-vs-0xC slip rejects every real EPROCESS.
                        # Layout is also resolved: this build (11/08, pid 20612) has name@+0x3a8
                        # and DirectoryTableBase@+0x98 (temp\_p20612_dump_out.txt); the older
                        # +0x338/+0x28 pair is kept as the second candidate.
                        o, noff, doff, d0c = None, 0, 0, 0
                        if b[i + 4] != 0:                   # tag must be NUL-terminated ("Process" is not)
                            i = b.find(b"Proc", i + 1)
                            continue
                        if i + 0x410 < len(b):
                            for cand in (i + 0xC, i + 0x10, i + 0x8):
                                for no2, do2 in LAYOUTS:
                                    if b[cand + no2:cand + no2 + 8] != b"r5apex_d":
                                        continue
                                    d2 = int(np.frombuffer(b[cand + do2:cand + do2 + 8], "<u8")[0])
                                    if d2 & 0xFFF == 0 and 0 < d2 < g.ram_top:
                                        o, noff, doff, d0c = cand, no2, do2, d2
                                        break
                                if o is not None:
                                    break
                        if o is None:
                            i = b.find(b"Proc", i + 1)
                            continue
                        seen += 1
                        seen_all += 1
                        if cal and len(calo) < 200:
                            po = None
                            k = b.find(pid.to_bytes(4, "little"), o, o + 0x400)
                            if k >= 0:
                                po = k - o
                            d0 = d0c
                            note = ""
                            pl, _e5 = rd(g, d0, 0x1000)
                            # A self-referencing PML4 has one entry whose frame is itself.  The
                            # (d0 >> 39) form is only right when the DTB's VA equals its PA.
                            if pl is not None:
                                ent = np.frombuffer(pl, "<u8")
                                if any(int(x) & ~0xFFF == d0 for x in ent):
                                    note = " DTB-OK"
                                    CAL_OK.append(d0)
                            say("  CAL obj=%#x nameoff=%#x dtb@+%#x=%#x pid_off=%s%s"
                                % (pa + o, noff, doff, d0, po if po is None else hex(po), note))
                            calo.append(pa + o)
                        # +0x3a8 name and +0x98 DTB are already proven by the base pick above.
                        d = d0c & ~0xFFF
                        if 0 < d < g.ram_top and len(procs) < 400:
                            has_pid = pid is None or pid in np.frombuffer(
                                b[o:o + 0x260], "<u4")
                            procs.append((pa + o, d, bool(has_pid)))
                        i = b.find(b"Proc", i + 1)
                i = b.find(dl.NAME)
                while i >= 0:
                    hits.append(pa + i)                 # NAME start, matches candidates_for
                    i = b.find(dl.NAME, i + 1)
                if not stop:
                    seeds_from(b, pa, seeds)
            swept += chunk
            if swept % (4 << 30) < chunk:
                say("  %4.0f s %.1f GB hits=%d seeds=%d"
                    % (time.time() - t0, swept / 1e9, len(hits) + len(procs), len(seeds)))
            if stop:
                break
            pa += chunk
    say("hits=%d seeds=%d tags_seen=%d in %.0fs"
        % (len(hits) + len(procs), len(seeds), seen_all, time.time() - t0))
    if cal and hits:
        say("--- calibration (%d hit(s)) ---" % len(hits))
        rows = []
        for h in hits[:12]:
            lo2 = max(0, h - 0x800)
            blk, e4 = rd(g, lo2, 0x880)
            if not blk:
                rows.append((1, "  %#x: no dump (%s)" % (h, e4)))
                continue
            rel = h - lo2
            for j in range(len(blk) - len(dl.NAME)):
                if not blk.startswith(dl.NAME, j):
                    continue
                base, oob = h - j, rel - j
                off28 = oob + 0x28
                if base < 0x1000 or not (0 <= off28 <= len(blk) - 8):
                    continue
                d = int(np.frombuffer(blk[off28:off28 + 8], "<u8")[0])
                po = [k - oob for k in range(oob, min(len(blk) - 4, oob + 0x800), 4)
                      if int(np.frombuffer(blk[k:k + 4], "<u4")[0]) == pid]
                note = ""
                if d & 0xFFF == 0 and 0 < d < g.ram_top:
                    pl, _e5 = rd(g, d, 0x1000)
                    if pl is not None and int(np.frombuffer(pl, "<u8")[(d >> 39) & 0x1FF]) \
                            & ~0xFFF == d:
                        note = " DTB-OK"
                rows.append((0 if po else 1,
                             "  hit %#x nameoff=%#x obj=%#x dtb@%#x=%#x%s pid_off=%s"
                             % (h, j, base, base + 0x28, d, note, [hex(x) for x in po][:6])))
        for _k, line in sorted(rows):
            say(line)
        return None, seeds
    if procs:
        procs.sort(key=lambda p: not p[2])              # pid-bearing objects first
        say("proc candidates=%d with_pid=%d" % (len(procs), sum(1 for p in procs if p[2])))
        for obj, d, hp in procs[:16]:
            pl, e3 = rd(g, d, 0x1000)
            if pl is None:
                say("  %#x dtb=%#x dead (%s)" % (obj, d, e3))
                continue
            if any(int(x) & ~0xFFF == d for x in np.frombuffer(pl, "<u8")):
                say("  %#x dtb=%#x LIVE self-ok pid=%s" % (obj, d, hp))
                return d, seeds
            say("  %#x dtb=%#x self-mismatch" % (obj, d))
        say("none of the first 16 candidates is a live PML4")
    for h in hits[:10]:
        say("  hit %#x" % h)
    if not hits:
        return None, seeds
    cands = dl.candidates_for(g, pid, hits)
    say("candidates=%d" % len(cands))
    if not cands:
        for h in hits[:3]:
            blk, e2 = rd(g, h - 0x340, 0x60)
            if blk:
                say("  around %#x: %s | %s"
                    % (h, " ".join("%9.3g" % x for x in np.frombuffer(blk, np.dtype("<f4"))[:12]),
                       " ".join("%#x" % x for x in np.frombuffer(blk, "<u8")[10:22])))
            else:
                say("  around %#x: %s" % (h, e2))
        return None, seeds
    return cands[0][2], seeds


def pick_seeds(seeds):
    """densest 64 KB bucket first: that is the entity array, a stray bone is not."""
    if not seeds:
        return []
    buckets = {}
    for s in seeds:
        buckets.setdefault(s >> 16, []).append(s)
    out = []
    for grp in sorted(buckets.values(), key=len, reverse=True):
        out.extend(sorted(grp))
    say("  seed buckets=%d densest=%d" % (len(buckets), max(len(v) for v in buckets.values())))
    return out


def probe(g, w, seed, span, near, cap):
    """resolve every pointer-looking qword around `seed` through the game's page tables."""
    base = (seed - span) & ~0xFFF
    b, err = rd(g, base, span * 2)
    if not b:
        say("  read failed: %s" % err)
        return [], []
    q = np.frombuffer(b, "<u8")
    cand = []
    for i in np.nonzero((q > CODE_LO) & (q < CODE_HI))[0]:
        off = i * 8 - span
        if abs(off) <= span - 8:
            cand.append((off, int(q[i])))
    say("  pointer-looking qwords=%d" % len(cand))
    if len(cand) > cap:
        cand = cand[:cap]
    frame = seed & ~0xFFF
    hits = []
    for off, va in cand:
        pa = w.page_pa(va)
        if pa is not None and abs(pa - frame) <= near:
            hits.append((off, va, pa))
    say("  resolved-hit=%d" % len(hits))
    for off, va, pa in hits:
        say("    %+#7x va=%#x page=%#x delta=%+#x" % (off, va, pa, pa - frame))
    runs, cur = [], []
    for k in range(len(hits)):
        if cur and hits[k][0] - cur[-1][0] == 8 and hits[k][2] == cur[-1][2]:
            cur.append(hits[k])
        else:
            if len(cur) >= 3:
                runs.append(cur)
            cur = [hits[k]]
    if len(cur) >= 3:
        runs.append(cur)
    say("  runs(>=3 into one frame)=%d" % len(runs))
    for r in runs:
        say("  RUN slot=%+#x n=%d frame=%#x" % (r[0][0], len(r), r[0][2]))
        slot, _e2 = rd(g, base + r[0][0], 0x60)
        if slot:
            say("    slot: %s" % " ".join("%#x" % x for x in np.frombuffer(slot, "<u8")))
    return hits, runs


def main():
    seed, span, near, cap = SEED, 0x1800, 0x200000, 400
    sweep, cal, frm, to = False, False, 0, None
    at_set = False
    for a in sys.argv:
        if a.startswith("--at="):
            seed, at_set = int(a.split("=", 1)[1], 0), True
        elif a.startswith("--from="):
            frm = int(a.split("=", 1)[1], 0)
        elif a.startswith("--to="):
            to = int(a.split("=", 1)[1], 0)
        elif a == "--cal":
            cal = True
        elif a.startswith("--span="):
            span = int(a.split("=", 1)[1], 0)
        elif a.startswith("--near="):
            near = int(a.split("=", 1)[1], 0)
        elif a.startswith("--cap="):
            cap = int(a.split("=", 1)[1], 0)
        elif a == "--sweep":
            sweep = True
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" %s' % (os.path.abspath(__file__),
                                         " ".join(sys.argv[1:]))))
        return 0
    open(OUT, "w").close()
    say("=== p142 owner scan v3 %s at=%#x%s span=%#x near=%#x ==="
        % (time.strftime("%H:%M:%S"), seed, " sweep" if sweep else "", span, near))
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: no game")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    g = gio.Gio(chunk=0x1000)
    dtb = 0
    for a in sys.argv:
        if a.startswith("--dtb="):
            dtb = int(a.split("=", 1)[1], 0)
    seeds = []
    if not dtb and "--use-cache" in sys.argv:
        try:
            c = int(open(CACHE, "r", encoding="utf-8").read().strip(), 0)
        except (OSError, ValueError):
            c = 0
        for _ in range(4):
            try:
                g.read_phys(c, 0x1000)
                dtb = c
                say("dtb from cache (PML4 reads)")
                break
            except OSError:
                pass
        if not dtb and c:
            say("cache %#x is dead, rescanning" % c)
    if not dtb:
        dtb, seeds = find_dtb(g, pid, proctag=("--names" not in sys.argv),
                              frm=frm, to=to, cal=cal)
        if cal:
            say("RESULT: calibration dump written, self-ref frames=%d" % len(CAL_OK))
            if CAL_OK:
                say("VERDICT: PASS - %#x reads and self-references (PML4)"
                    % CAL_OK[0])
            else:
                say("VERDICT: FAIL - no candidate page both reads and self-references")
            return 0
        if dtb is None:
            say("RESULT: no DTB")
            say("VERDICT: FAIL - could not establish the game CR3")
            return 1
        with open(CACHE, "w", encoding="utf-8") as f:
            f.write("%#x\n" % dtb)
    say("dtb=%#x seeds=%d" % (dtb, len(seeds)))
    w = None
    for k in range(12):
        try:
            w = dl.Walk(g, dtb)
            break
        except OSError as e:
            say("  walk try %d: %s" % (k + 1, e))
            time.sleep(0.1)
    if w is None:
        say("RESULT: dtb=%#x walk=dead" % dtb)
        say("VERDICT: FAIL - PML4 read kept failing (1450)")
        return 1
    if at_set:
        todo = [seed]
    else:
        todo = pick_seeds(seeds)[:3]
        if not todo:
            say("RESULT: dtb=%#x seeds=0" % dtb)
            say("VERDICT: FAIL - sweep found no record heads (pools moved?)")
            return 1
    tot_h, tot_r = 0, 0
    for k, s in enumerate(todo):
        say("seed %d/%d = %#x%s" % (k + 1, len(todo), s, " (cli)" if at_set else
                                     " (bucket %#x)" % (s >> 16)))
        hits, runs = probe(g, w, s, span, near, cap)
        tot_h, tot_r = tot_h + len(hits), tot_r + len(runs)
        if runs:
            seed = s
            break
    g.close()
    say("RESULT: dtb=%#x seeds_tried=%d hits=%d runs=%d" % (dtb, len(todo), tot_h, tot_r))
    if tot_r:
        say("VERDICT: PASS - component array run(s) found at %#x" % seed)
    elif tot_h:
        say("VERDICT: PARTIAL - lone references only (no TArray run)")
    else:
        say("VERDICT: FAIL - no reference into the seed frame")
    return 0 if tot_r else (2 if tot_h else 1)


if __name__ == "__main__":
    sys.exit(main())
