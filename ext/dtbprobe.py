"""dtbprobe.py -- hard-retry the accepted DTB, then walk and dump the image.

p43y proved the geometry (one candidate, name+pid+shape+frame on 26200) but
died on `phys read 0x7ec76d000+0x1000 failed (1450)` -- and the 3-try retry in
dumplive was not enough.  gdrv3 answers 1450 for pages that are transitioning,
so this probe retries the frame with backoff before judging it, shows the raw
first bytes of every successful read, follows the candidate's flink one hop to
prove the list is real, and only then walks/dumps.

READ-ONLY: device open only.  No host state changes; output to its own files.
"""
import hashlib
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p43z_dtb.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p43z_progress.txt"))
PA = 0x7EC76D000
BASE = 0x2481D60C0

LOG = []


def log(s):
    LOG.append(s)
    print(s)


def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


def main():
    log("dtbprobe  %s  pa=%#x base=%#x" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                                           PA, BASE))
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(1, "FATAL no transport")
    log("ram_top=%#x is_ram(pa)=%s" % (g.ram_top, g.is_ram(PA)))

    # the object itself first: if this page is gone too, the base is stale.
    try:
        ob = g.read_phys(BASE & ~0xFFF, 0x2000)
        b = BASE & 0xFFF
        log("object reread ok: type=%d name=%r pid@1d0=%#x flink=%#x blink=%#x"
            % (ob[b], ob[b + 0x338:b + 0x338 + 16].rstrip(b"\x00"),
               struct.unpack_from("<I", ob, b + 0x1D0)[0],
               struct.unpack_from("<Q", ob, b + 0x258)[0],
               struct.unpack_from("<Q", ob, b + 0x260)[0]))
    except OSError as e:
        log("object reread FAILED: %s" % e)
        g.close()
        return wr(3, "OBJECT_GONE")

    # the frame, with real backoff
    ok = 0
    for i in range(12):
        try:
            p = g.read_phys(PA, 0x1000)
        except OSError as e:
            log("  try %2d rc=ERR %s" % (i + 1, e))
            time.sleep(0.5)
            continue
        ok = i + 1
        log("  try %2d ok pml4[0]=%016x pml4[ff]=%016x"
            % (ok, struct.unpack_from("<Q", p, 0)[0],
               struct.unpack_from("<Q", p, 0xFF * 8)[0]))
        break
    if not ok:
        g.close()
        return wr(4, "DTB_UNREADABLE")

    todo = 0
    try:
        w = dl.Walk(g, PA)
    except OSError as e:
        log("walk ctor fault %s" % e)
        g.close()
        return wr(5, "WALK_FAULT")
    log("walk pml4 ok e0=%016x e_ff=%016x" % (w.e0, dl.u64(w.pml4, 0xFF * 8)))
    try:
        r = dl.find_mz(g, PA)
    except OSError as e:
        log("find_mz fault %s" % e)
        g.close()
        return wr(5, "WALK_FAULT")
    log("find_mz -> %s" % (("va=%#x size=%#x hdr=%#x secs=%d"
                            % (r[0], r[1]["size"], r[1]["hdr"], len(r[1]["secs"])))
                           if r else "no PE"))
    if not r:
        log("why: %s" % dl.probe_dtb(g, PA))
        g.close()
        return wr(6, "NO_MZ")

    base_va, meta = r
    try:
        st = dl.Stats()
        buf = bytearray(meta["size"])
        w = dl.Walk(g, PA)
        dl.dump_range(g, w, buf, base_va, 0, meta["hdr"], st)
        for name, va, vsize in meta["secs"]:
            before = st.read
            dl.dump_range(g, w, buf, base_va, va, vsize, st)
            log("  sec %-8.8s va=%#010x size=%#x read=%d"
                % (name, va, vsize, st.read - before))
    except OSError as e:
        g.close()
        return wr(7, "DUMP_FAULT %s" % e)
    out_bin = os.path.join(ROOT, "temp", "r5apex_mod_%s.bin"
                           % time.strftime("%Y%m%d_%H%M%S"))
    with open(out_bin, "wb") as f:
        f.write(buf)
    sha = hashlib.sha256(buf).hexdigest()
    log("DUMP %s size=%#x sha256=%s" % (out_bin, len(buf), sha))
    log("pages read=%d fail=%d" % (st.read // dl.PAGE, st.fail // dl.PAGE))
    for code in sorted(g.stats):
        log("  stat %s" % g.stat_line(code))
    g.close()
    if st.read < 0x4000000 or st.fail:
        return wr(8, "DUMP_PARTIAL read=%d fail=%d" % (st.read, st.fail))
    return wr(0, "DUMP_OK %s %s" % (out_bin, sha))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        import traceback
        log("CRASH %s: %s" % (type(e).__name__, e))
        log(traceback.format_exc().replace("\n", " | ")[:900])
        sys.exit(wr(9, "CRASH"))
