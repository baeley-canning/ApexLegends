r"""p92_refresh.py -- p85's target sweep with the close order inverted.

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

Usage: python temp\p92_refresh.py [maxpages]     (elevated; the arm queue is)

maxpages (default 64) caps how many distinct hit pages the shape stage reads.
Three p88/p86 runs bugchecked at 0x3b inside that stage; the cap plus the
per-page prog() checkpoint turns "died somewhere after the scan" into a named
page, and READ/SHAPE/PAGECAP lines survive the crash that kills the log.

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

OUT = os.path.join(HERE, "_p92_refresh.txt")
TGT = os.path.join(HERE, "_p92_targets.txt")
# p72_ppath repoints dl.OUT at temp\p72_out.txt on import; give p91 its own.
dl.OUT = OUT
dl.PROG = os.path.join(HERE, "_p92_prog.txt")
NAME = b"Code.exe"
# p86/p88 chain died three times between PIDSCANEND and the first shape line
# (0x3b c0000005, twice) and left nothing behind: every post-scan line went
# through log(), which is memory-only.  The loop is now checkpointed per page in
# prog(), RAM-gated on both ends of the page, retried like pid_scan does, and
# capped so one run cannot sit in the crashing stage indefinitely.
MAXPAGES = int(sys.argv[1]) if len(sys.argv) > 1 else 1200

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
    """26200 EPROCESS head gate at object base `b` inside page `p`."""
    if b < 0 or b + 0x350 > gio.PAGE:
        return False, "offset"
    if p[b] != 3:
        return False, "type=%d" % p[b]
    nm = p[b + 0x338:b + 0x338 + 15].rstrip(b"\x00")
    if nm != NAME:
        return False, "name=%r" % nm
    return True, ""


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
    dl.prog("=== p92 start %s maxpages=%d"
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
        ranges, note = dl.usable_ranges(g.ram_top)
        log("RAMMAP %s ranges=%d total=%d MiB"
            % (note, len(ranges), sum(b - a for a, b in ranges) >> 20))
        hits, faults = pp.pid_scan(g, ranges, pid, cap=200000)
        log("pid scan: %d occurrences fault=%d %.1f s"
            % (len(hits), faults, time.perf_counter() - dl._T0))

        cache, good = {}, []
        vhits = [pa for pa in hits
                 if 0x1D0 <= (pa & 0xFFF) <= gio.PAGE - 0x350]
        viable = len(vhits)
        vpages = {pa & ~0xFFF for pa in vhits}
        dl.prog("SHAPESTART hits=%d viable=%d pages=%d cap=%d t=%.0fs"
                % (len(hits), viable, len(vpages), MAXPAGES,
                   time.perf_counter() - dl._T0))
        for i, pa in enumerate(vhits):
            b = (pa & 0xFFF) - 0x1D0
            # Offset-window filter *before* the cap: a hit whose lane cannot carry
            # an object head (b < 0 or head past the page) would otherwise burn
            # a cap slot and a read.  64 pages of this ate the whole 09:52 budget on
            # `no (offset)` and never reached the object.
            if b < 0 or b + 0x350 > gio.PAGE:
                continue
            page = pa & ~0xFFF
            if page not in cache:
                if MAXPAGES and len(cache) >= MAXPAGES:
                    dl.prog("PAGECAP stop i=%d page=%#x" % (i, page))
                    break
                dl.prog("READ i=%d page=%#x" % (i, page))
                if not (g.is_ram(page) and g.is_ram(page + 0xFFF)):
                    cache[page] = None
                    dl.prog("  skip non-RAM page %#x" % page)
                else:
                    try:
                        cache[page] = dl.retry_phys(g, page, gio.PAGE)
                        dl.prog("  ok %#x" % page)
                    except OSError as e:
                        cache[page] = None
                        dl.prog("  fault %#x err=%s" % (page, e.errno or 0))
            p = cache[page]
            if p is None:
                continue
            ok, why2 = shape(p, b)
            dl.prog("  shape pa=%#x base=%#x %s%s"
                    % (pa, page + b, "SHAPE" if ok else "no",
                       "" if ok else " (" + why2 + ")"))
            if ok:
                good.append(page + b)
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

