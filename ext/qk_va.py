r"""qk_va.py -- ZERO-ATTACH virtual-address reader (PLAN stage 1b / 2).

WHY THIS EXISTS
    apexdrv reads do one KeStackAttachProcess per IOCTL.  On 07/11 that was
    followed by EAAC terminating the game twice (ExitType 0x322327458D1ED790,
    14 s and ~4 min after the read bursts).  gdrv3 has swept 9 GB of physical
    memory with ZERO Javelin events, and its read path (MmMapIoSpace in the
    caller's own context) never attaches to the game's address space.

    So: read physically, walk the page tables ourselves, and the only kernel
    footprint is the resident gdrv3 image.  That is the shape with evidence of
    survival, and it is the Stage 1b gate: 10 minutes of 1 Hz reads with no
    Javelin event.

DTB
    Cached in temp\qk_dtb_<pid>.txt together with the image base, so only the
    first run of a game session pays the discovery (~70-80 s via p72_ppath's
    pid scan).  A new game process => new pid => fresh discovery.

USAGE
    python ext\qk_va.py --pe                     # image base + MZ + sections
    python ext\qk_va.py --at=0x7FF721690000 --len=64
    python ext\qk_va.py --array=0xB675E68 --slots=64     # pointer array -> entities
    python ext\qk_va.py --watch=600 --at=<base>          # Stage 1b survival gate

EXIT   0 ok | 2 no driver | 3 no game | 4 no dtb | 5 read failed
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio            # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
TMP = os.path.join(ROOT, "temp")

LOG = []
OUT_PATH = None


def set_out(p):
    """Truncate the evidence file and remember it; every line is appended live."""
    global OUT_PATH
    OUT_PATH = os.path.abspath(p) if p else None
    if OUT_PATH:
        try:
            os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
            with open(OUT_PATH, "w", encoding="utf-8") as f:
                f.write("")
        except OSError:
            pass


def out(s):
    line = str(s)
    print(line)
    LOG.append(line)
    if OUT_PATH:
        try:
            with open(OUT_PATH, "a", encoding="utf-8") as f:   # live: tail-able
                f.write(line + "\n")
        except OSError:
            pass


def flush(path):
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(LOG) + "\n")
    except OSError as e:
        print("could not write %s: %s" % (path, e))


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def flag(name):
    return ("--" + name) in sys.argv


# --------------------------------------------------------------- DTB cache
def dtb_file(pid):
    return os.path.join(TMP, "qk_dtb_%d.txt" % pid)


def load_cached(pid):
    p = dtb_file(pid)
    if not os.path.exists(p):
        return None
    try:
        with open(p, "r", encoding="utf-8") as f:
            k = {}
            for ln in f:
                if "=" in ln:
                    a, b = ln.strip().split("=", 1)
                    k[a] = int(b, 16) if b.lower().startswith("0x") else int(b)
            if k.get("pid") == pid and k.get("dtb"):
                return k
    except (OSError, ValueError):
        return None
    return None


def save_cache(pid, dtb, base):
    try:
        os.makedirs(TMP, exist_ok=True)
        with open(dtb_file(pid), "w", encoding="utf-8") as f:
            f.write("pid=%d\ndtb=0x%X\nbase=0x%X\nstamp=%d\n"
                    % (pid, dtb, base or 0, int(time.time())))
    except OSError:
        pass


# --------------------------------------------------------------- reader
class Reader(object):
    """VA -> PA through the page tables, then a physical read.  No attach."""

    def __init__(self, g, dtb):
        self.g = g
        self.w = dl.Walk(g, dtb)
        self.dtb = dtb
        self.reads = 0
        self.faults = 0

    def page_pa(self, va):
        return self.w.page_pa(va)

    def read(self, va, n):
        buf = bytearray()
        left = n
        cur = va
        while left > 0:
            pa = self.w.page_pa(cur)
            if pa is None:
                self.faults += 1
                return None
            off = cur & 0xFFF
            take = min(left, 0x1000 - off)
            try:
                b = self.g.read_phys(pa + off, take)
            except OSError:
                self.faults += 1
                return None
            self.reads += 1
            buf += b
            cur += take
            left -= take
        return bytes(buf)

    def u64(self, va):
        b = self.read(va, 8)
        return None if b is None else struct.unpack("<Q", b)[0]

    def u32(self, va):
        b = self.read(va, 4)
        return None if b is None else struct.unpack("<I", b)[0]


# --------------------------------------------------------------- discovery
def discover(g, pid):
    """DTB + image base through dumplive's 26200 shape gate.

    p72_ppath.front_pid assumed EPROCESS pid at +0x1D0 / name at +0x338 and
    rejected every hit on this build (measured: 45 hits, name garbage, dtb=0x0).
    dumplive is the code written FOR 26200: sweep for the ImageFileName string,
    then require name-at-base + pid-in-range + valid_cr3 + shape score, and only
    then walk to an MZ page.  Layout-agnostic and already battle-tested here.
    """
    def _route(s):
        out("    | " + str(s))

    dl.log = _route
    out("  discovering DTB for pid %d (name sweep + shape gate, ~80 s) ..." % pid)
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        out("    ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))
        hits, skipped, chunks, rescued = dl.name_hits(g, ranges)
        out("    name hits=%d chunks=%d skipped=%d rescued=%d"
            % (len(hits), chunks, skipped, rescued))
        if not hits:
            out("  no ImageFileName hits - wrong game/build, or nothing running")
            return None
        cands = dl.candidates_for(g, pid, hits)
        out("    shape-gate candidates=%d" % len(cands))
        for score, ebase, dtb in cands[:8]:
            out("    cand score=%d eprocess=%#x dtb=%#x" % (score, ebase, dtb))
            try:
                r = dl.find_mz(g, dtb)
            except OSError as e:
                out("      walk fault: %s" % e)
                continue
            if r:
                out("    walk -> image_va=%#x sections=%d" % (r[0], len(r[1].get("secs", []))))
                return {"dtb": dtb, "base": r[0]}
        out("  no candidate walked to an MZ image")
    except Exception as e:                      # noqa: BLE001
        out("  discovery fault: %s: %s" % (type(e).__name__, e))
    return None


def get_map(g, pid):
    """cached (dtb, base) if it still walks to an MZ, else discover + cache."""
    c = load_cached(pid)
    if c:
        try:
            rd = Reader(g, c["dtb"])
            mz = rd.read(c["base"], 2)
        except OSError:
            mz = None
        if mz == b"MZ":
            out("  dtb cache hit: dtb=0x%X base=0x%X" % (c["dtb"], c["base"]))
            return c
        out("  dtb cache stale (no MZ at cached base) - re-discovering")
    d = discover(g, pid)
    if d:
        save_cache(pid, d["dtb"], d["base"])
    return d


# --------------------------------------------------------------- actions
def hexdump(b, va, n=16):
    rows = []
    for i in range(0, len(b), n):
        chunk = b[i:i + n]
        rows.append("  %#012x  %s  |%s|" % (
            va + i,
            " ".join("%02X" % x for x in chunk).ljust(n * 3 - 1),
            "".join(chr(x) if 32 <= x < 127 else "." for x in chunk)))
    return rows


SETS = {
    "B": {"origin": 0x330, "alive": 0x5DC, "hp": 0x5E0, "shield": 0x5E8,
          "team": 0x10E8, "name": 0x10F0},
    "A": {"origin": 0x258, "health": 0x3A0, "team": 0x478},
}


def decode(rd, ent, idx):
    """Score both candidate field sets on one entity.  Returns (a, b)."""
    buf = rd.read(ent + 0x200, 0x400)
    out("  [%d] ent=%#x" % (idx, ent))
    if buf is None:
        out("        read[0x400@+0x200] FAULT")
        return 0, 0
    s = {0x330: 0, 0x258: 0}
    for tag, base in (("B", 0x200), ("A", 0x200)):
        f = SETS[tag]
        off = f["origin"] - base
        x, y, z = struct.unpack_from("<fff", buf, off)
        if tag == "B":
            alive, hp, sh = struct.unpack_from("<iii", buf, f["alive"] - base)
            out("        B: origin=(%.1f, %.1f, %.1f) alive=%d hp=%d shield=%d"
                % (x, y, z, alive, hp, sh))
            sb = 0
            if all(v == v and abs(v) < 1e6 for v in (x, y, z)) and (x or y or z):
                sb += 2
            if 0 < hp <= 200:
                sb += 2
            if 0 <= sh <= 200:
                sb += 1
            if alive in (0, 1, 2):
                sb += 1
            s["B"] = sb
        else:
            hp = struct.unpack_from("<i", buf, f["health"] - base)[0]
            out("        A: origin=(%.1f, %.1f, %.1f) health=%d" % (x, y, z, hp))
            sa = 0
            if all(v == v and abs(v) < 1e6 for v in (x, y, z)) and (x or y or z):
                sa += 2
            if 0 < hp <= 200:
                sa += 2
            s["A"] = sa
    tail = rd.read(ent + 0x10D8, 0x40)
    if tail is not None:
        team, namep = struct.unpack_from("<iQ", tail, SETS["B"]["team"] - 0x10D8)
        out("        B: team=%d namePtr=%#x" % (team, namep))
        if 0 <= team <= 64:
            s["B"] += 2
        if 0x10000 <= namep <= 0x7FFFFFFFFFFF and (namep & 7) == 0:
            s["B"] += 1
            raw = rd.read(namep, 32)
            if raw:
                txt = "".join(chr(w) for w in struct.unpack_from("<16H", raw)
                              if 32 <= w < 127)
                out("        name: \"%s\"" % (txt or "(non-printable)"))
    out("        score: A=%d B=%d" % (s["A"], s["B"]))
    return s["A"], s["B"]


def act_pe(rd, base):
    mz = rd.read(base, 2)
    out("  base=%#x MZ=%r" % (base, mz))
    if mz != b"MZ":
        return 4
    lf = struct.unpack("<I", rd.read(base + 0x3C, 4))[0]
    hdr = rd.read(base + lf, 0x108)
    if hdr is None:
        return 5
    machine, nsec = struct.unpack_from("<HH", hdr, 4)
    stamp = struct.unpack_from("<I", hdr, 8)[0]
    size = struct.unpack_from("<I", hdr, 0x50)[0]
    out("  PE machine=%#06x sections=%d stamp=%d SizeOfImage=%#x (%.1f MB)"
        % (machine, nsec, stamp, size, size / 1048576.0))

def act_array(rd, va, slots, ents):
    out("  array=%#x slots=%d" % (va, slots))
    found = []
    for i in range(slots):
        v = rd.u64(va + i * 8)
        if v and 0x10000 <= v <= 0x7FFFFFFFFFFF and (v & 7) == 0:
            found.append((i, v))
    out("  canonical slots: %d of %d" % (len(found), slots))
    for i, v in found[:8]:
        out("    slot[%d] = %#x" % (i, v))
    sum_a = sum_b = 0
    n = 0
    for i, v in found[:ents]:
        a, b = decode(rd, v, i)
        sum_a += a
        sum_b += b
        n += 1
    out("  ----")
    out("  decoded=%d scoreA=%d scoreB=%d reads=%d faults=%d"
        % (n, sum_a, sum_b, rd.reads, rd.faults))
    if n == 0:
        out("  RESULT: no-entities")
        out("  VERDICT: PARTIAL - no canonical slots at this address")
        return 8
    if sum_b > sum_a:
        out("  RESULT: setB-leads A=%d B=%d" % (sum_a, sum_b))
        out("  VERDICT: PASS - candidate set B decodes on a live object array (zero attach)")
        return 0
    if sum_a > sum_b:
        out("  RESULT: setA-leads A=%d B=%d" % (sum_a, sum_b))
        out("  VERDICT: PASS - candidate set A decodes on a live object array (zero attach)")
        return 0
    out("  RESULT: ambiguous A=%d B=%d" % (sum_a, sum_b))
    out("  VERDICT: PARTIAL - neither field set decodes cleanly")
    return 9


def act_watch(rd, at, secs, pid):
    out("  Stage 1b gate: %ds of 1 Hz zero-attach reads at %#x" % (secs, at))
    t0 = time.perf_counter()
    n = good = 0
    while time.perf_counter() - t0 < secs:
        b = rd.read(at, 4)
        n += 1
        if b is not None:
            good += 1
        alive = 1
        try:
            alive = 1 if dl.pid_alive(pid) else 0
        except Exception:                       # noqa: BLE001
            alive = -1
        out("  T+%02ds read=%s pid_alive=%d reads=%d faults=%d"
            % (int(time.perf_counter() - t0), (b.hex() if b is not None else "FAULT"),
               alive, rd.reads, rd.faults))
        if alive == 0:
            out("  target died at T+%ds (check the Application log for Javelin 1000)"
                % int(time.perf_counter() - t0))
            break
        time.sleep(max(0.05, 1.0 - ((time.perf_counter() - t0) % 1.0)))
    el = int(time.perf_counter() - t0)
    out("  ALIVE reads=%d ok=%d elapsed=%ds" % (n, good, el))
    out("  RESULT: watch good=%d/%d reads=%d faults=%d" % (good, n, rd.reads, rd.faults))
    if good == n and n > 0:
        out("  VERDICT: PASS - %ds of zero-attach reads, target alive; now confirm the "
            "Application log has NO 'EA Javelin Anticheat' 1000 in this window" % el)
        return 0
    out("  VERDICT: PARTIAL - %d of %d reads faulted" % (n - good, n))
    return 5


# --------------------------------------------------------------- main
def main():
    out_path = arg("out", os.path.join(TMP, "qk_va_%s.txt" % time.strftime("%Y%m%d_%H%M%S")))
    set_out(out_path)

    if not dl.elevation() and not flag("no-elevate"):
        # ABSOLUTE script path: run_elevated() starts the child in ext\, so a
        # relative "ext\qk_va.py" would resolve to ext\ext\qk_va.py and die
        # silently before writing anything (measured: 4 runs, 0 files).
        argv = [os.path.abspath(sys.argv[0])] + [a for a in sys.argv[1:] if a != "--no-elevate"]
        if not any(a.startswith("--out") for a in argv):
            argv.append("--out=" + OUT_PATH)
        cmd = " ".join('"%s"' % a if " " in a else a for a in argv)
        out("not elevated - relaunching elevated (the gdrv3 device DACL needs it)")
        res = dl.run_elevated(cmd)
        out(res)
        return 0

    out("===== qk_va v1 (zero-attach VA read: gdrv3 physical + own page walk) =====")
    out("out=%s" % out_path)

    try:
        g = gio.Gio()
    except OSError as e:
        out("gio open failed: %s (gdrv3 not running, or not elevated)" % e)
        out("VERDICT: PARTIAL - no transport")
        flush(out_path)
        return 2

    rc = 0
    try:
        pid = arg("pid", 0, lambda s: int(s, 0)) or 0
        if not pid:
            try:
                pid = int(dl.find_pid() or 0)
            except Exception:                   # noqa: BLE001
                pid = 0
        if not pid:
            out("no r5apex process and no --pid")
            out("VERDICT: PARTIAL - target absent")
            return 3
        out("target pid=%d" % pid)

        m = get_map(g, pid)
        if not m:
            out("RESULT: no-dtb")
            out("VERDICT: FAIL - page tables not resolved (the pid scan output above says why)")
            return 4
        rd = Reader(g, m["dtb"])
        base = m["base"]

        if flag("pe"):
            rc = act_pe(rd, base)
        elif arg("array", 0, lambda s: int(s, 0)):
            rc = act_array(rd, arg("array", 0, lambda s: int(s, 0)),
                           arg("slots", 64, lambda s: int(s, 0)),
                           arg("ents", 4, lambda s: int(s, 0)))
        elif arg("watch", 0, lambda s: int(s, 0)):
            rc = act_watch(rd, arg("at", base, lambda s: int(s, 0)),
                           arg("watch", 0, lambda s: int(s, 0)), pid)
        else:
            at = arg("at", base, lambda s: int(s, 0))
            ln = arg("len", 64, lambda s: int(s, 0))
            b = rd.read(at, ln)
            if b is None:
                out("  RESULT: fault at %#x" % at)
                out("  VERDICT: FAIL - page not present through the walk")
                rc = 5
            else:
                out("  read %d bytes at %#x" % (len(b), at))
                for row in hexdump(b, at):
                    out(row)
                out("  RESULT: ok reads=%d faults=%d" % (rd.reads, rd.faults))
                out("  VERDICT: PASS - zero-attach VA read")
    finally:
        try:
            g.close()
        except Exception:                       # noqa: BLE001
            pass
        flush(out_path)
    return rc


if __name__ == "__main__":
    sys.exit(main())


