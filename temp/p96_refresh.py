r"""p96_refresh.py -- p85's sweep, name-anchored gate with a correct name compare.

p91/p92 (dst-last close) both survived teardown -- bugcheck fixed -- but all of
p91..p95 returned no target on a *live* process.  p95's name-anchored fallback
found the reason: it printed `type=3 name=b'Code.exe\\x00'` over and over -- real
process objects, correct base, correct offset -- and rejected every single one.

`shape()` compared `rstrip(b"\\x00") == NAME`.  The 15-byte ImageFileName field is
not zero-padded past the terminator when an object is reused, so rstrip leaves the
residue after the NUL and equality can never hold.  p96 splits the field at the
NUL and compares the C-string, so those objects pass.  The pid lanes at
0x1d0/0x1d8/0x1e0/0x1e8 are now printed on every attempt, and an object whose lane
carries the chosen pid is preferred (PIDPICK) over a name-only match -- the lane is
measured instead of assumed.

p84 was written against pid 18592's EPROCESS page (0x6d98a1000) and PML4 frame
(0x6f04bf000).  pid 18592 died in the 08:31 bugcheck, so both constants are
stale: a sweep with them measures a recycled page, not the process.

p84 was written against pid 18592's EPROCESS page (0x6d98a1000) and PML4 frame
(0x6f04bf000).  pid 18592 died in the 08:31 bugcheck, so both constants are
stale: a sweep with them measures a recycled page, not the process.

What this does (reads only, device open + close):
  1. pick the earliest-starting Code.exe (p83's stability rule: the root
     browser process outlives its renderers) and prove it alive,
  2. pid-dword scan over OS-declared usable RAM, gate every hit on the 26200
     object shape -- dispatcher type 3 at base, pid lane at +0x1d0, the
     ImageFileName "Code.exe" at +0x338 -- and keep the candidates,
  3. read the winning control page twice (0x40 bytes at the base offset) so a
     recycled page is visible instead of assumed,
  4. read DirectoryTableBase (+0x28) and probe the frame: a frame that refuses
     is exactly what p84 calls BAD.

Output is keyed to one pid in temp\_p85_targets.txt (PID=/EPROCESS=/CTL=/DTB=/
BAD=/BAD_STATE=) so p84 cannot pick a different page by accident, and the full
log is temp\_p85_refresh.txt.  Nothing is restored because nothing is changed.

Usage: python temp\p96_refresh.py [maxpages] [resume_pa_hex]   (elevated; the arm
queue is)

maxpages (default 64) caps how many distinct hit pages the shape stage reads.
Three p88/p86 runs bugchecked at 0x3b inside that stage; the cap plus the
per-page prog() checkpoint turns "died somewhere after the scan" into a named
page, and READ/SHAPE/PAGECAP lines survive the crash that kills the log.

resume_pa_hex (default 0x100000) starts the pid scan at that PA instead of
re-walking the map from the bottom.  A fault that is a property of the address
(p104 `PINNED_FAULT`: 0x200000, err 1450 on 3/3 tries, three runs, three landing
buffers, control read green) is skipped by the plan (BADPA already brackets it),
never re-bought page by page; pages lost anyway are hopped with a budget so a
dead device still stops the scan instead of crawling 4 GiB.  The scan must be
able to name a hole *and* still finish.

p91 variant: p90's os._exit proved the bugcheck is *not* CPython finalisation --
the box still went down 0x3B/0xC0000005 and WER names the same instruction every
time, gdrv3+0x2e81 `mov dword ptr [r14+rdx*4], eax`.  That is a dword memcpy
whose count comes from the request size field and whose *destination* faults, so
something writes into the scratch buffer after gio.close() released it
(VirtualFree MEM_RELEASE ran before CloseHandle).  p91 inverts that order
(GIO_DST_LAST=1); sweep, gates, output keys and the os._exit tail are unchanged
so the verdict stays comparable with p85's.
"""
import os
os.environ.setdefault("GIO_DST_LAST", "1")    # must precede the gio import
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402
import dumplive as dl  # noqa: E402
import p72_ppath as pp  # noqa: E402

OUT = os.path.join(HERE, "_p96_refresh.txt")
TGT = os.path.join(HERE, "_p96_targets.txt")
# p72_ppath repoints dl.OUT at temp\p72_out.txt on import; give p91 its own.
dl.OUT = OUT
dl.PROG = os.path.join(HERE, "_p96_prog.txt")
NAME = b"Code.exe"
# p86/p88 chain died three times between PIDSCANEND and the first shape line
# (0x3b c0000005, twice) and left nothing behind: every post-scan line went
# through log(), which is memory-only.  The loop is now checkpointed per page in
# prog(), RAM-gated on both ends of the page, retried like pid_scan does, and
# capped so one run cannot sit in the crashing stage indefinitely.
MAXPAGES = int(sys.argv[1]) if len(sys.argv) > 1 else 4000
# p100 was cut short at 0x200000; resume above it instead of re-walking 3 MiB.
RESUME = int(sys.argv[2], 16) if len(sys.argv) > 2 else dl.SCAN_LO

PS = ("Get-Process Code -ErrorAction SilentlyContinue | "
      "ForEach-Object { '{0} {1}' -f $_.StartTime.ToFileTime(), $_.Id }")


def pick_pid():
    """Earliest-starting Code.exe -> (pid, candidates, why)."""
    r = subprocess.run(["powershell", "-NoProfile", "-Command", PS],
                       capture_output=True, text=True)
    rows = []
    for ln in r.stdout.splitlines():
        f = ln.split()
        if len(f) == 2 and f[0].isdigit() and f[1].isdigit():
            rows.append((int(f[0]), int(f[1])))
    rows.sort()
    if not rows:
        return 0, rows, "no Code.exe"
    return rows[0][1], rows, "earliest of %d" % len(rows)


def alive(pid):
    return subprocess.run(["powershell", "-NoProfile", "-Command",
                           "(Get-Process -Id %d -EA Stop).Id" % pid],
                          capture_output=True).returncode == 0


def shape(p, b):
    """26200 EPROCESS head gate at object base `b` inside buffer `p`.

    p96: the name comparison was `rstrip(b"\\x00") == NAME`, which can never match.
    The 15-byte ImageFileName field is not zero-padded past the terminator on a
    reused object -- p95 printed `type=3 name=b'Code.exe\\x00'` for dozens of real
    objects and rejected every one.  A reused EPROCESS keeps residue after its NUL,
    so compare the C-string (`split(b"\\x00")[0]`) instead.  The pid lanes around
    0x1d0 are printed on both outcomes: the object whose lane carries the chosen
    pid is the one to keep, and the lane is a measurement rather than a belief.
    """
    if b < 0 or b + 0x352 > len(p):
        return False, "offset b=%#x len=%#x" % (b, len(p))
    lan = [struct.unpack_from("<I", p, b + o)[0] for o in (0x1D0, 0x1D8, 0x1E0, 0x1E8)]
    lans = ",".join("%#x" % v for v in lan)
    nm = p[b + 0x338:b + 0x352].split(b"\x00")[0]
    if nm != NAME:
        return False, "type=%d name=%r lanes=%s" % (p[b], nm[:12], lans)
    return True, "type=%d lanes=%s" % (p[b], lans)


def main():
    # log() used to be dl.log, i.e. memory-only: the 10:01:45 crash fired ~26 s
    # after WRITE_TARGETS and took the whole tail of this log with it, leaving an
    # all-NUL targets file and no _p85_refresh.txt — "finished but unflushed" and
    # "died in the post-target code" were indistinguishable.  Every line now goes
    # to disk (flush + fsync) so the last durable line names the stage.
    open(OUT, "w", encoding="utf-8").close()

    def log(msg):
        dl.log(msg)
        try:
            with open(OUT, "a", encoding="utf-8") as fh:
                fh.write(msg + "\n")
                fh.flush()
                os.fsync(fh.fileno())
        except OSError:
            pass

    log("p92 refresh (dst-last close, repeat)  %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    log("pure-read: device open + close, no writes")
    dl.prog("=== p96 start %s maxpages=%d"
            % (time.strftime("%Y%m%d_%H%M%S"), MAXPAGES))
    pid, cands, why = pick_pid()
    for ft, p in cands:
        log("  cand pid=%d start=%s" % (p, time.strftime(
            "%H:%M:%S", time.localtime(ft / 1e7 - 11644473600))))
    if not pid:
        return finish(log, "NO_PID")
    log("chosen pid=%d (%s)" % (pid, why))
    if not alive(pid):
        return finish(log, "PID_DEAD")
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        return finish(log, "FATAL open %s" % e)

    verdict = "NO_SHAPE"
    try:
        ranges, note = dl.usable_ranges(g.ram_top, lo=RESUME)
        log("RAMMAP %s ranges=%d total=%d MiB lo=%#x hopmax=%d stride=%d"
            % (note, len(ranges), sum(b - a for a, b in ranges) >> 20,
               RESUME, dl.HOP_MAX, dl.HOP_STRIDE))
        hits, faults = pp.pid_scan(g, ranges, pid, cap=200000,
                                   hopmax=dl.HOP_MAX, stride=dl.HOP_STRIDE)
        log("pid scan: %d occurrences fault=%d skipped=%s %.1f s"
            % (len(hits), faults,
               "SCANSTOP" if dl.SCAN_STOPPED else "no", time.perf_counter() - dl._T0))
        # The pocket's two edges, whatever the outcome: lastbad is where the walk
        # gave up or stopped losing pages, firstgood is the RAM it could read
        # again.  Both are prog lines as well, so a crash cannot eat them.
        if dl.HOP_LAST:
            log("EDGE lastbad=%#x firstgood=%#x hops=%d stride=%d"
                % (dl.HOP_LAST, dl.FIRST_GOOD, faults, dl.HOP_STRIDE))
            dl.prog("EDGE lastbad=%#x firstgood=%#x hops=%d stride=%d"
                    % (dl.HOP_LAST, dl.FIRST_GOOD, faults, dl.HOP_STRIDE))
        if dl.SCAN_STOPPED and not hits:
            # Nothing at all past the hole and the budget is gone: the device,
            # not the address, is the suspect - say so instead of NO_SHAPE.
            return finish(log, "SCANSTOP hopmax=%d" % dl.HOP_MAX)

        cache, good = {}, []
        vhits = [pa for pa in hits if 0x1D0 <= (pa & 0xFFF) < gio.PAGE]
        viable = len(vhits)
        vpages = {pa & ~0xFFF for pa in vhits}
        dl.prog("SHAPESTART hits=%d viable=%d pages=%d cap=%d t=%.0fs"
                % (len(hits), viable, len(vpages), MAXPAGES,
                   time.perf_counter() - dl._T0))
        for i, pa in enumerate(vhits):
            b = (pa & 0xFFF) - 0x1D0
            # The head is 0x350 bytes, but an EPROCESS can be placed so that it runs
            # past the page end.  The old filter dropped every base with
            # b + 0x350 > PAGE before it was read, so an object in the last 0x350 of
            # a page was invisible -- p91 and p92 both returned good=0 for a live
            # process because of it.  The lane window above now admits those hits
            # and the read below spans two pages when the head would cross.
            page = pa & ~0xFFF
            need = b + 0x350
            stale = page in cache and cache[page] is not None and len(cache[page]) < need
            if page not in cache or stale:
                if page not in cache and MAXPAGES and len(cache) >= MAXPAGES:
                    dl.prog("PAGECAP stop i=%d page=%#x" % (i, page))
                    break
                span = 0x2000 if need > gio.PAGE else gio.PAGE
                dl.prog("READ i=%d page=%#x b=%#x span=%#x%s"
                        % (i, page, b, span, " (widen)" if stale else ""))
                if not (g.is_ram(page) and g.is_ram(page + span - 1)):
                    cache[page] = None
                    dl.prog("  skip non-RAM page %#x" % page)
                else:
                    try:
                        cache[page] = dl.retry_phys(g, page, span)
                    except OSError as e:
                        cache[page] = None
                        if span == gio.PAGE:
                            dl.prog("  fault %#x err=%s" % (page, e.errno or 0))
                        else:
                            # neighbour missing (top of RAM): the head may still fit
                            try:
                                cache[page] = dl.retry_phys(g, page, gio.PAGE)
                                dl.prog("  short %#x err=%s" % (page, e.errno or 0))
                            except OSError as e2:
                                cache[page] = None
                                dl.prog("  fault %#x err=%s" % (page, e2.errno or 0))
                    else:
                        dl.prog("  ok %#x len=%#x" % (page, len(cache[page])))
            p = cache[page]
            if p is None:
                continue
            ok, why2 = shape(p, b)
            dl.prog("  shape pa=%#x base=%#x %s%s"
                    % (pa, page + b, "SHAPE" if ok else "no",
                       "" if ok else " (" + why2 + ")"))
            if ok:
                good.append(page + b)
        # p95 fallback, name-anchored: search every page that was actually read for
        # the image name and test base = name - 0x338 with no reference to the pid
        # lane at all.  This is what makes the probe diagnostic rather than another
        # guess -- if the lane moved, the object still turns up here.
        seen, names, goodpid = set(good), 0, []
        for page, p in list(cache.items()):
            if p is None:
                continue
            pos = p.find(NAME)
            while pos >= 0:
                names += 1
                b2 = pos - 0x338
                if b2 >= 0 and (page + b2) not in seen:
                    ok2, why3 = shape(p, b2)
                    dl.prog("  NAMESHAPE page=%#x base=%#x %s%s"
                            % (page, page + b2, "SHAPE" if ok2 else "no",
                               "" if ok2 else " (" + why3 + ")"))
                    if ok2:
                        good.append(page + b2)
                        seen.add(page + b2)
                        if struct.unpack_from("<I", p, b2 + 0x1D0)[0] == pid:
                            goodpid.append(page + b2)
                pos = p.find(NAME, pos + 1)
        dl.prog("NAMEDONE names=%d good=%d pidmatch=%d t=%.0fs"
                % (names, len(good), len(goodpid),
                   time.perf_counter() - dl._T0))
        if goodpid:
            # the object whose lane carries our pid wins, name-only matches follow
            good = goodpid + [x for x in good if x not in goodpid]
            dl.prog("PIDPICK base=%#x n=%d" % (good[0], len(goodpid)))
        dl.prog("SHAPEDONE good=%d pages=%d t=%.0fs"
                % (len(good), len(cache), time.perf_counter() - dl._T0))
        if not good:
            return finish(log, verdict)

        base = good[0]
        ctl = base & ~0xFFF
        off = base & 0xFFF
        # R3: two reads of the same 0x40 window, before anything points at it.
        dl.prog("CTLREAD ctl=%#x off=%#x t=%.0fs"
                % (ctl, off, time.perf_counter() - dl._T0))
        try:
            a = g.read_phys_checked(ctl + off, 0x40)
            time.sleep(0.05)
            b2 = g.read_phys_checked(ctl + off, 0x40)
        except OSError as e:
            return finish(log, "CTL_FAULT %s" % e)
        log("control page %#x base %#x read1=%s read2=%s stable=%s"
            % (ctl, base, a[:8].hex(), b2[:8].hex(), a == b2))
        dl.prog("CTLSTABLE %s read1=%s" % (a == b2, a[:8].hex()))
        if a != b2:
            return finish(log, "CTL_UNSTABLE")
        dtb = struct.unpack_from("<Q", a, 0x28)[0]
        dl.prog("DTB dtb=%#x valid_cr3=%s"
                % (dtb, dl.valid_cr3(g, dtb)))
        log("dtb=%#x valid_cr3=%s" % (dtb, dl.valid_cr3(g, dtb)))

        # BAD: the DTB frame if it refuses; otherwise the first refusing frame
        # below it, so the p84 sweep still carries a negative control.
        bad, state = 0, "none"
        if dtb:
            try:
                g.read_phys_checked(dtb, 8)
                log("dtb reads: searching for a refusing frame")
                dl.prog("BADSEARCH dtb reads")
            except OSError as e:
                bad, state = dtb, "dtb_refuses err=%d" % (e.errno or 0)
                log("dtb refuses (%s) -> BAD" % e)
            if not bad:
                for k in range(1, 65):
                    pa = (dtb & ~0xFFF) - k * gio.PAGE
                    if not g.is_ram(pa):
                        dl.prog("BADSTOP non-RAM %#x at k=%d" % (pa, k))
                        break
                    try:
                        g.read_phys_checked(pa, 8)
                    except OSError as e:
                        bad, state = pa, "probe_refuses err=%d" % (e.errno or 0)
                        dl.prog("BAD hit %#x k=%d" % (pa, k))
                        break
        if not bad:
            bad, state = dtb, "all_read"
        dl.prog("BADEPICK bad=%#x state=%s" % (bad, state))

        if not alive(pid):
            return finish(log, "PID_DIED")
        write_targets(dict(PID=pid, EPROCESS=base, CTL=ctl, DTB=dtb, BAD=bad,
                           BAD_STATE=state))
        dl.prog("WRITE_TARGETS pid=%d base=%#x ctl=%#x dtb=%#x bad=%#x"
                % (pid, base, ctl, dtb, bad))
        log("TARGETS pid=%d base=%#x ctl=%#x dtb=%#x bad=%#x (%s)"
            % (pid, base, ctl, dtb, bad, state))
        verdict = "TARGETS_OK" if bad and bad != ctl else "TARGETS_PARTIAL"
        return finish(log, verdict)
    finally:
        g.close()
        dl.prog("CLOSED t=%.0fs" % (time.perf_counter() - dl._T0))


def write_targets(d):
    # flush + fsync: the 10:01 run committed the *size* of this file and none of
    # its bytes, so p88's keyed() read 143 NULs.  An fsync makes the targets
    # survive the crash that keeps following this stage.
    with open(TGT, "w", encoding="utf-8") as f:
        f.write("PID=%d\nEPROCESS=%#x\nCTL=%#x\nDTB=%#x\nBAD=%#x\n"
                "BAD_STATE=%s\nSTAMP=%s\n"
                % (d["PID"], d["EPROCESS"], d["CTL"], d["DTB"], d["BAD"],
                   d["BAD_STATE"], time.strftime("%Y-%m-%d %H:%M:%S")))
        f.flush()
        os.fsync(f.fileno())


def finish(log, verdict):
    dl.prog("FINISH_BEGIN verdict=%s" % verdict.split()[0])
    log("VERDICT: %s" % verdict)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(dl.LOG) + "\n")
        f.flush()
        os.fsync(f.fileno())
    dl.prog("FINISH_DONE")
    return 0 if verdict.startswith("TARGETS") else 1


if __name__ == "__main__":
    try:
        rc = main()
    except Exception:
        import traceback
        dl.log("EXC " + traceback.format_exc().replace("\n", " | "))
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(dl.LOG) + "\n")
            f.flush()
            os.fsync(f.fileno())
        rc = 1
    # Hard exit (p90): the 10:17 run wrote CLOSED and the machine bugchecked ~3 s
    # later, before the parent p88 ever logged an rc -- so the fault sits in
    # CPython finalisation (ctypes releasing gdrv3.dll) and/or the DLL unload, not
    # in close() or finish().  Everything above is fsynced already, so os._exit
    # loses nothing and skips finalisation + FreeLibrary entirely.
    sys.stdout.flush()
    sys.stderr.flush()
    dl.prog("EXITING rc=%d" % rc)
    os._exit(rc)





