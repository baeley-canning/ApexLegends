r"""Current-process binding with existing GIOV3 MapK only.

Pool tag is FOUR ASCII bytes `Proc`, not `Proc\0`. Previous code's NUL
requirement discarded live objects. Use the two locally measured layouts,
and require correct process name, exact live PID, and process type. A DTB is
used only after its own physical page resolves PEB.ImageBaseAddress to Apex's
full PE header. Nothing else here infers player entities from arbitrary RAM.
"""
import struct
import time

import qk_va
import dumplive as dl
import qk_gdrv_mapread
import qk_bridge


def proc_candidates(g, pid, log, budget=160):
    r = g.mapread
    found = {}
    t0 = time.time()
    pages = tags = 0
    for lo, hi in r.ranges:
        pa = lo
        while pa + 0x1000 <= hi and time.time() - t0 < budget:
            try:
                b = r.read(pa, 0x1000)
            except OSError:
                pa += 0x1000
                continue
            pages += 1
            at = b.find(b"Proc")
            checked = 0
            while at >= 0 and checked < 48:
                checked += 1
                tags += 1
                # Pool tag lives at object-0xC, so i+0xC is the object base.
                # Keep the older variants only for existing measured layouts.
                for cand in (at + 0xC, at + 0x10, at + 8):
                    for noff, toff, doff, poff in (
                            (0x338, 0, 0x28, 0x1D0),
                            (0x3A8, 0x70, 0x98, 0x240)):
                        if cand + noff + 15 > 0x1000:
                            continue
                        if b[cand+noff:cand+noff+15] != b"r5apex_dx12.ex\0":
                            continue
                        if b[cand+toff] != 3:
                            continue
                        if struct.unpack_from("<I", b, cand+poff)[0] != pid:
                            continue
                        dtb = struct.unpack_from("<Q", b, cand+doff)[0] & dl.MASK
                        if r.in_ram(dtb, 0x1000):
                            found[pa+cand] = (dtb, noff)
                            log("OBJECT obj=%#x nameoff=%#x DTB=%#x" %
                                (pa+cand, noff, dtb))
                at = b.find(b"Proc", at+1)
            if pages % 1000000 == 0:
                log("pages=%d GB=%.1f tags=%d candidates=%d elapsed=%.1fs" %
                    (pages, pages*4096/1e9, tags, len(found), time.time()-t0))
            pa += 0x1000
    log("SCAN_DONE pages=%d tags=%d accepted_objects=%d time=%.1fs" %
        (pages, tags, len(found), time.time()-t0))
    return found


def bind_current(g, pid, log):
    peb = qk_va._peb_va(pid)
    log("PID=%d PEB=%#x" % (pid, peb))
    if not peb:
        return None
    for obj, (dtb, noff) in proc_candidates(g, pid, log).items():
        try:
            rd = qk_va.Reader(g, dtb)
            raw = rd.read(peb + 0x10, 8)
            if not raw:
                continue
            base = struct.unpack("<Q", raw)[0]
            page = rd.read(base, 0x1000)
            meta = dl.validate_pe(page) if page else None
            log("DTB=%#x object=%#x base=%#x PE=%s" % (dtb, obj, base, meta))
            if meta and meta["size"] == 0xDFB8000:
                qk_va.save_cache(pid, dtb, base)
                log("RESULT: DTB=%#x base=%#x image_pa=%s" %
                    (dtb, base, rd.page_pa(base)))
                return {"dtb": dtb, "base": base, "obj": obj}
        except OSError as e:
            log("walk error obj=%#x err=%s" % (obj, e))
    log("VERDICT: BLOCKED - no valid process module proof")
    return None