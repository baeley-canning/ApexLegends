r"""h320_va.py -- external live entity reader over the gdrv3 phys primitive.

Milestone P1: compose the accepted pieces (gio phys read, dumplive DTB
discovery, p72 overlay for the unreadable PML4 frame) into a *virtual address*
reader, then walk the game's dynamic entity list and print name/team/hp/shield/
position per entity, with a world-to-screen check against the view matrix.

Nothing is injected.  The only kernel footprint is the resident gdrv3 image,
which is exactly the variable under test.

Usage:
  h320_va.py --needle=Name1 --needle=Name2 [--secs=180] [--hz=2]
             [--out=_ritual\h320_va1.txt] [--max-ent=120] [--w=2560 --h=1440]
             [--overlay=_ritual\p72_overlay.txt] [--dtb=0x4E47FC000]

Offsets (Apex a0, from build_quick_test.py):
  entity_list 0x23F6A90   view_matrix 0x1B4DFA0
  ent: +0x5DC alive +0x5E0 hp +0x5E8 shield +0x10E8 team +0x10F0 name
       +0x330 origin
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)

ENT_LIST = 0x23F6A90
VIEWMAT = 0x1B4DFA0
OFF_ALIVE = 0x5DC
OFF_HP = 0x5E0
OFF_SHIELD = 0x5E8
OFF_TEAM = 0x10E8
OFF_NAME = 0x10F0
OFF_ORIGIN = 0x330

PAGE = 0x1000
LOG = []
FORCE_DTB = 0
DTB_WAIT = 90          # s to wait out a transient 1450 on a candidate dtb frame


def log(s):
    stamp = time.strftime("%H:%M:%S", time.localtime())
    line = "%s %s" % (stamp, s)
    LOG.append(line)
    print(line, flush=True)
    if LOG_PATH:
        try:
            with open(LOG_PATH, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        except OSError:
            pass


class VaWalk(object):
    """Read process virtual memory through its DTB, one page at a time.

    Entries are read with the same 1450-retry dumplive uses; successfully read
    frames are cached because the entity list revisits the same few tables.
    """

    def __init__(self, g, dtb, cache_pages=256):
        self.g = g
        self.dtb = dtb & dl.MASK
        self.cache = {}
        self.cache_max = cache_pages
        self.faults = 0
        self.hits = 0

    def _frame(self, pa):
        pa &= dl.MASK
        buf = self.cache.get(pa)
        if buf is not None:
            self.hits += 1
            return buf
        try:
            buf = dl.retry_phys(self.g, pa, PAGE, tries=4)
        except Exception:
            buf = None
        if buf is None or len(buf) < PAGE:
            self.faults += 1
            return None
        if len(self.cache) >= self.cache_max:
            self.cache.clear()
        self.cache[pa] = buf
        return buf

    def _entry(self, table_pa, idx):
        buf = self._frame(table_pa)
        if buf is None:
            return None
        return struct.unpack_from("<Q", buf, idx * 8)[0]

    def pa_of(self, va):
        """Translate va through PML4..PT; big pages handled at 1G/2M."""
        e = self._entry(self.dtb, (va >> 39) & 0x1FF)
        if e is None:
            return None
        if e & 0x1:
            e = self._entry(e, (va >> 30) & 0x1FF)
            if e is None:
                return None
            if e & 0x1:
                if e & 0x80:                      # 1 GiB page
                    return (e & dl.MASK & ~0x3FFFFFFF) | (va & 0x3FFFFFFF)
                e = self._entry(e, (va >> 21) & 0x1FF)
                if e is None:
                    return None
                if e & 0x1:
                    if e & 0x80:                  # 2 MiB page
                        return (e & dl.MASK & ~0x1FFFFF) | (va & 0x1FFFFF)
                    e = self._entry(e, (va >> 12) & 0x1FF)
                    if e is None or not (e & 0x1):
                        return None
        return (e & dl.MASK) | (va & 0xFFF)

    def read(self, va, n):
        out = b""
        left = n
        cur = va
        while left > 0:
            pa = self.pa_of(cur)
            if pa is None:
                break
            take = min(left, PAGE - (cur & 0xFFF))
            buf = self._frame(pa)
            if buf is None:
                break
            out += buf[cur & 0xFFF: (cur & 0xFFF) + take]
            cur += take
            left -= take
        return out

    def u64(self, va):
        b = self.read(va, 8)
        return struct.unpack("<Q", b)[0] if len(b) == 8 else None

    def u32(self, va):
        b = self.read(va, 4)
        return struct.unpack("<I", b)[0] if len(b) == 4 else None

    def i32(self, va):
        b = self.read(va, 4)
        return struct.unpack("<i", b)[0] if len(b) == 4 else None

    def f32(self, va):
        b = self.read(va, 4)
        return struct.unpack("<f", b)[0] if len(b) == 4 else None

    def u8(self, va):
        b = self.read(va, 1)
        return b[0] if len(b) == 1 else None

    def cstr(self, va, cap=32):
        b = self.read(va, cap)
        z = b.find(b"\x00")
        if z >= 0:
            b = b[:z]
        return b.decode("latin-1", "replace")


LOG_PATH = None
OVERLAY = None


def w2s(m16, w, h, pos):
    """World -> screen.  Returns (x, y) or None when behind the camera."""
    if not pos or len(pos) != 3:
        return None
    x, y, z = pos
    cw = m16[12] * x + m16[13] * y + m16[14] * z + m16[15]
    if cw < 0.01:
        return None
    cx = m16[0] * x + m16[1] * y + m16[2] * z + m16[3]
    cy = m16[4] * x + m16[5] * y + m16[6] * z + m16[7]
    sx = (w * 0.5) * (1.0 + cx / cw)
    sy = (h * 0.5) * (1.0 - cy / cw)
    return sx, sy


def matrix(walk, base):
    b = walk.read(base + VIEWMAT, 64)
    if len(b) != 64:
        return None
    return struct.unpack("<16f", b)


def entity(walk, ent):
    """One entity snapshot.  None when the pointer or shape is unusable."""
    if not ent or ent < 0x10000 or ent > 0x7FFFFFFFFFFF:
        return None
    team = walk.i32(ent + OFF_TEAM)
    if team is None or team < 0 or team > 100:
        return None
    hp = walk.i32(ent + OFF_HP)
    shield = walk.i32(ent + OFF_SHIELD)
    if hp is None or shield is None:
        return None
    if hp < 0 or hp > 500 or shield < 0 or shield > 500:
        return None
    alive = walk.u8(ent + OFF_ALIVE)
    pos = walk.read(ent + OFF_ORIGIN, 12)
    xyz = struct.unpack("<3f", pos) if len(pos) == 12 else None
    if xyz is not None:
        for c in xyz:
            if c != c or abs(c) > 200000.0:
                xyz = None
                break
    name = walk.cstr(ent + OFF_NAME)
    if not name or not name[0].isalnum():
        name = "?"
    return {"ent": ent, "name": name, "team": team, "hp": hp,
            "shield": shield, "alive": alive, "pos": xyz}


def tick(walk, base, max_ent, w, h, seq):
    """One sampling pass.  Returns (lines, plausible count)."""
    lines = []
    gm = walk.u64(base + ENT_LIST)
    if not gm:
        return ["seq=%d entity_list unreadable" % seq], 0
    m16 = matrix(walk, base)
    found = 0
    for i in range(max_ent):
        ent = walk.u64(gm + 8 * i)
        if ent is None:
            break
        e = entity(walk, ent)
        if e is None:
            continue
        found += 1
        scr = w2s(m16, w, h, e["pos"]) if m16 else None
        if scr:
            where = "S=(%4.0f,%4.0f)" % scr
        elif e["pos"]:
            where = "S=off"
        else:
            where = "S=nopos"
        pos = ("p=(%.1f %.1f %.1f)" % e["pos"]) if e["pos"] else "p=?"
        lines.append("seq=%d i=%02d ent=%012X team=%d hp=%3d sh=%3d alv=%s %-20s %s %s"
                     % (seq, i, e["ent"], e["team"], e["hp"], e["shield"],
                        e["alive"], e["name"], pos, where))
    return lines, found


def discover(needles):
    """pid -> needle scan -> candidate DTB -> module base.  Picks the first
    candidate with a validated PE image; logs every reject."""
    pid = dl.find_pid()
    if not pid:
        return None, None, "game not running"
    log("pid=%d" % pid)
    g = gio.Gio()
    if OVERLAY:
        try:
            import p72_root
            g = p72_root.wrap(g, OVERLAY)
            log("overlay on (%s)" % OVERLAY)
        except Exception as ex:
            log("overlay failed: %s" % ex)
    ranges, note = dl.usable_ranges(g.ram_top)
    log("rammap %s ranges=%d" % (note, len(ranges)))
    hits, _sk, _ck, _rs = dl.name_hits(g, ranges)
    log("name hits=%d skipped=%d chunks=%d rescued=%d" % (len(hits), _sk, _ck, _rs))
    if not hits:
        g.close()
        return None, None, "no name hits"
    cands = dl.candidates_for(g, pid, hits)
    log("dtb candidates=%d" % len(cands))
    time.sleep(0.3)                       # let 1450 pressure from the sweep drop
    # h320: an EPROCESS DTB that lands in an MmPhysicalMemoryBlock hole cannot
    # be mapped (1450/31) and the whole run used to die on it.  The accepted
    # base is still the real object, so offer the other qwords of the KPROCESS
    # head as fallbacks -- each must pass valid_cr3, find_mz is the verdict.
    if cands:
        score0, ebase, dtb0 = cands[0]
        log("cand dtb %012X ebase=%012X score=%d" % (dtb0, ebase, score0))
        extra = []
        for off in range(0x18, 0x48, 8):
            try:
                d = struct.unpack("<Q", g.read_phys(ebase + off, 8))[0]
            except OSError:
                continue
            if d and d != dtb0 and dl.valid_cr3(g, d):
                extra.append((score0 - 1, ebase, d))
                log("alt dtb %012X from ebase%+#x" % (d, off))
        cands = cands + extra
    # --dtb= repairs discovery when the real frame is unmappable (p331): the
    # forced frame is prepended but still gated by valid_cr3 + find_mz verdict.
    if FORCE_DTB:
        if dl.valid_cr3(g, FORCE_DTB):
            cands = [(999, 0, FORCE_DTB & dl.MASK)] + \
                    [c for c in cands if c[2] != (FORCE_DTB & dl.MASK)]
            log("forced dtb %012X (valid_cr3 ok)" % FORCE_DTB)
        else:
            log("forced dtb %012X REJECTED by valid_cr3" % FORCE_DTB)
    for score, ebase, dtb in cands:
        try:
            r = dl.find_mz(g, dtb)
        except OSError as ex:
            # p332: 1450 on the dtb frame is transient (the same frame read clean
            # minutes later), so poll instead of discarding the candidate.
            if ex.errno == 1450:
                log("dtb %012X: walk fault 1450, waiting (max %ds)" %
                    (dtb, DTB_WAIT))
                t_wait = time.time() + DTB_WAIT
                r = None
                while time.time() < t_wait:
                    time.sleep(1.0)
                    try:
                        r = dl.find_mz(g, dtb)
                    except OSError as ex2:
                        if ex2.errno != 1450:
                            log("dtb %012X: walk fault %s" % (dtb, ex2))
                            break
                        continue
                    break
                if not r:
                    log("dtb %012X: still no PE after wait" % dtb)
                    continue
            else:
                log("dtb %012X: walk fault %s" % (dtb, ex))
                continue
        if not r:
            log("dtb %012X: no PE" % dtb)
            continue
        base, meta = r
        if not base:
            log("dtb %012X: empty base" % dtb)
            continue
        log("dtb %012X ACCEPT eproc=%012X base=%012X size=%#x" %
            (dtb, ebase, base, meta["size"]))
        return g, (VaWalk(g, dtb), base), ""
    g.close()
    return None, None, "no accepting dtb"


def main(argv):
    global LOG_PATH, OVERLAY, FORCE_DTB
    needles = []
    secs, hz, out, max_ent, w, h = 180.0, 1.0, "h320_va1.txt", 128, 2560, 1440
    for a in argv:
        if a.startswith("--needle="):
            needles.append(a.split("=", 1)[1])
        elif a.startswith("--dtb="):
            FORCE_DTB = int(a.split("=", 1)[1], 0)
        elif a.startswith("--secs="):
            secs = float(a.split("=")[1])
        elif a.startswith("--hz="):
            hz = float(a.split("=")[1])
        elif a.startswith("--out="):
            out = a.split("=", 1)[1]
        elif a.startswith("--max-ent="):
            max_ent = int(a.split("=")[1], 0)
        elif a.startswith("--w="):
            w = int(a.split("=")[1])
        elif a.startswith("--h="):
            h = int(a.split("=")[1])
        elif a.startswith("--overlay="):
            OVERLAY = a.split("=", 1)[1]
    if not needles:
        needles = ["r5apex_dx12.ex"]          # EPROCESS ImageFileName, 15 chars
    LOG_PATH = out if os.path.isabs(out) else os.path.join(ROOT, out)
    with open(LOG_PATH, "w", encoding="utf-8") as fh:
        fh.write("h320_va needle=%s secs=%g hz=%g screen=%dx%d\n"
                 % (",".join(needles), secs, hz, w, h))
    log("start %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    g, got, why = discover(",".join(needles))
    if not g:
        log("discover FAIL: %s" % why)
        log("VERDICT: FAIL no dtb (%s)" % why)
        return 2
    walk, base = got
    t0 = time.time()
    seqpass = passn = 0
    best = 0
    try:
        while time.time() - t0 < secs:
            ticks = time.time()
            seqpass += 1
            lines, n = tick(walk, base, max_ent, w, h, seqpass)
            for ln in lines:
                log(ln)
            best = max(best, n)
            if n >= 3:
                passn += 1
            log("tick %d n=%d faults=%d cache_hits=%d"
                % (seqpass, n, walk.faults, walk.hits))
            dt = hz - (time.time() - ticks)
            if dt > 0:
                time.sleep(dt)
    finally:
        try:
            g.close()
        except Exception:
            pass
    ratio = (100.0 * passn / seqpass) if seqpass else 0.0
    log("ticks=%d pass=%d ratio=%.0f%% best=%d faults=%d"
        % (seqpass, passn, ratio, best, walk.faults))
    if passn == 0:
        verdict = "FAIL no plausible entities"
    elif ratio < 50.0:
        verdict = "MARGINAL pass %.0f%% best %d" % (ratio, best)
    else:
        verdict = "PASS entities live (%d/tick best, %.0f%% ticks)" % (best, ratio)
    log("VERDICT: %s" % verdict)
    return 0 if passn else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

