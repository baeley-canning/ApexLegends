r"""qk_live.py -- external candidate projection, an overlay, and a menu.

The matrix and candidate records are read inside the same tick, but independent
physical reads are NOT frame-atomic.  A failed read invalidates its record; stale
values are never silently reused.  Projection candidates must come from a fresh,
PID-matched, player-validated JSON source: _p134_out.txt is a world/component
analysis log, NOT a validated player list, and is quarantined by default.

What it reads (through the already-loaded GIOV3, no new driver load, no attach):

  matrix   image_pa + vp_rva   from temp\\qk_offsets.txt (the boot's own record)
  players  --census=path, version-1 JSON with per-record position offsets/roles

Every raw physical read is guarded by the RAM-map interval set (R10).

What it draws: a click-through, colour-keyed, topmost layered window covering the
game's client area; boxes on the census entities; a menu whose toggles change what
is drawn and whose state survives a restart (temp\\qk_live_cfg.txt).

usage:
  python ext\qk_live.py --fake [--seconds=20]   no game, no driver, no elevation
  python ext\qk_live.py --check                 live read-back, ~3 s, needs elevation
  python ext\qk_live.py --run [--hz=20] [--fps=60] [--seconds=0] [--wide]
                                                --hz ladder {10,20,30,60,120,144};
                                                others fall back to default (M3.1)
  python ext\qk_live.py --wide                  also try matrix windows +-0x1000
                                                --fps also tunes --fake/--from-feed; 0 = uncapped
  --expiry-zeros=3              void observations before a census record is retired
                                for its census generation (M1 auto-expiry); 0 disables

verdicts go to temp\\qk_live_out.txt (append-only per run, prefixed by mode), the
one-line live feed to temp\\qk_live_status.txt, so the state is a file, not a
screenshot someone has to squint at (R3).
"""
import ctypes
import ctypes.wintypes as wt
import json
import math
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

TMP = os.path.join(ROOT, "temp")
OFFS = os.path.join(TMP, "qk_offsets.txt")
CENSUS = os.path.join(TMP, "_p134_out.txt")
PLAYER_ROLES = ("player", "remote_player", "local_player")
OUT = os.path.join(TMP, "qk_live_out.txt")
STATUS = os.path.join(TMP, "qk_live_status.txt")
CFG = os.path.join(TMP, "qk_live_cfg.txt")

# --- what a box is -----------------------------------------------------------
HEAD_Z = 72.0                 # head offset above the origin, Apex world units
BOX_W = 0.55                  # box width as a fraction of its height
BOX_MAX_W = 420.0
SEED_BYTES = 0xC0             # a census record; positions() needs this much
SEED_TRIPLE = (0, 1, 2)       # legacy contiguous scan ONLY; not a world transform
COMPONENT_TRIPLE = (0, 16, 32)  # p135/p141 measured (x,r,r,0)(y,0,0,s)(z,...)
DEFAULT_EXPIRY_ZEROS = 3       # M1: void reads before a census PA retires (0 = off)
MIN_CLIENT_W, MIN_CLIENT_H = 320, 200

# --- colours (COLORREF = 0x00BBGGRR) ----------------------------------------
SCHEMES = (
    ("cyan",   0x00FFFF00, 0x00C0C000),
    ("green",  0x0000FF40, 0x0000C030),
    ("red",    0x004040FF, 0x003030C0),
    ("magenta",0x00FF40FF, 0x00C030C0),
)
KEY_BLACK = 0x00000000        # colorkey: this exact colour is transparent

_logf = None


def out(s=""):
    line = str(s)
    print(line)
    if _logf is not None:
        _logf.write(line + "\n")
        _logf.flush()


def status(s):
    try:
        with open(STATUS, "w", encoding="utf-8") as f:
            f.write(s + "\n")
    except OSError:
        pass


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def flag(name):
    return ("--" + name) in sys.argv


def now():
    return time.strftime("%H:%M:%S")


def _key(argname, default):
    p = "--" + argname + "="
    for a in sys.argv:
        if a.startswith(p):
            return a[len(p):]
    return default


# ---------------------------------------------------------------------------
# the boot's own records
# ---------------------------------------------------------------------------
def offsets_file(path=OFFS):
    """{image_pa, vp_rva, ...} written by the probe that found them."""
    m = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.split("=", 1)
                    m[k.strip()] = v.strip()
    except OSError:
        pass
    return m


def census_seeds(path=CENSUS):
    """Census PAs in file order, first occurrence only, capped by the caller."""
    pas = []
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                mm = re.match(r"\s*@0x([0-9a-fA-F]+)", line)
                if mm:
                    pa = int(mm.group(1), 16)
                    if pa not in pas:
                        pas.append(pa)
    except OSError:
        return []
    return pas


def _timestamp_value(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def read_seed_source(path=CENSUS, pid=None, now=None, max_age=900.0,
                     allow_unverified=False):
    """Return candidates together with independently reportable source gates.

    Preferred input is a versioned JSON document produced by a future player-
    validated discovery pass. Each player-role record declares its PA, offsets,
    role/local association, and a nonempty ``owner_ref`` and ``class_name``.
    ``player_validated`` is a producer attestation; this consumer checks the
    evidence fields' presence, not the truth of an owner/class chain. Legacy logs
    are parsed ONLY from structured ``SEED`` records;
    the old ``@`` collision with _p134 coordinates is no longer accepted.
    Legacy candidates are diagnostic-only, even in --allow-unverified mode.
    """
    started = time.time() if now is None else now
    info = {"path": os.path.abspath(path), "format": "missing", "pid": None,
            "captured_ts": 0.0, "player_validated": False, "records": [],
            "unbound_records": 0, "gate": "missing", "allow_unverified": allow_unverified}
    if not os.path.isfile(path):
        return info
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read()
        mtime = os.path.getmtime(path)
    except OSError as e:
        info["gate"] = "read_error"
        info["error"] = str(e)
        return info
    if raw.lstrip().startswith("{"):
        try:
            doc = json.loads(raw)
            if doc.get("version") != 1 or not isinstance(doc.get("records"), list):
                raise ValueError("expected version=1 and records=[]")
            info.update(format="json", pid=doc.get("pid"),
                        captured_ts=_timestamp_value(doc.get("captured_ts")),
                        player_validated=doc.get("player_validated") is True,
                        layout=doc.get("layout", "unspecified"))
            unique = set()
            for rec in doc["records"]:
                raw_pa = rec["pa"]
                pa = int(raw_pa, 0) if isinstance(raw_pa, str) else int(raw_pa)
                off = tuple(int(i) for i in rec.get("position_offsets", ()))
                if pa <= 0 or pa in unique or not off:
                    continue
                unique.add(pa)
                role = rec.get("role", "unknown")
                owner_ref = rec.get("owner_ref")
                class_name = rec.get("class_name")
                owner_ref = owner_ref.strip() if isinstance(owner_ref, str) else ""
                class_name = class_name.strip() if isinstance(class_name, str) else ""
                # Evidence is supplied by the producer; its presence is not an
                # independent proof by this consumer.  Missing linkage is never
                # good enough to turn a player-validated flag into a RAM read.
                if role in PLAYER_ROLES and (not owner_ref or not class_name):
                    info["unbound_records"] += 1
                info["records"].append({"pa": pa, "indices": off, "role": role,
                                        "owner_ref": owner_ref, "class_name": class_name,
                                        "local": rec.get("local") is True,
                                        "layout": rec.get("layout", info["layout"]),
                                        "fields": rec.get("fields")})  # M2: declared cells, validated downstream
        except (ValueError, TypeError, KeyError, json.JSONDecodeError) as e:
            info["records"] = []
            info["gate"] = "invalid_json"
            info["error"] = str(e)
            return info
    else:
        info["format"] = "legacy_log"
        info["captured_ts"] = mtime
        pids = [int(v) for v in re.findall(r"^\s*game_pid=(\d+)\s*$", raw, re.M)]
        if pids:
            info["pid"] = pids[-1]
        seeds = set(int(v, 16) for v in
                    re.findall(r"^\s*SEED\s+0x([0-9a-fA-F]+)\s*$", raw, re.M))
        layout = "component3x4" if "owner scan" in raw or "component3x4" in raw else \
                 "unverified_contiguous"
        indices = COMPONENT_TRIPLE if layout == "component3x4" else SEED_TRIPLE
        info.update(layout=layout, records=[
            {"pa": pa, "indices": indices, "role": "world_component_unverified",
             "layout": layout, "local": False} for pa in sorted(seeds)])
    if not info["records"]:
        info["gate"] = "no_records"
        return info
    if info["unbound_records"]:
        info["gate"] = "owner_class_unverified"
        return info
    if not info["player_validated"]:
        info["gate"] = "player_type_unverified"
        return info
    if not info["pid"]:
        info["gate"] = "pid_missing"
        return info
    if pid is not None and info["pid"] != pid:
        info["gate"] = "pid_mismatch"
        return info
    if not (0 < info["captured_ts"] <= started + 5.0):
        info["gate"] = "timestamp_invalid"
        return info
    info["age_seconds"] = max(0.0, started - info["captured_ts"])
    if max_age > 0 and info["age_seconds"] > max_age:
        info["gate"] = "stale"
        return info
    info["gate"] = "candidate_eligible"
    return info


def source_summary(src):
    return ("source=%s pid=%s age=%s layout=%s player_validated=%s records=%d unbound=%d gate=%s"
            % (os.path.basename(src["path"]), src.get("pid"),
               ("%.1fs" % src["age_seconds"]) if src.get("age_seconds") is not None else "?",
               src.get("layout", "?"), src.get("player_validated"),
               len(src["records"]), src.get("unbound_records", 0), src["gate"]))


# ---------------------------------------------------------------------------
# physical reads, inside the RAM map's interval set only (R10)
# ---------------------------------------------------------------------------
class Phys(object):
    CHUNK = 0x10000

    def __init__(self):
        import gio
        import dumplive as dl
        self.gio = gio
        self.dl = dl
        self.g = gio.Gio(chunk=self.CHUNK)
        self.ranges, self.note = dl.usable_ranges(self.g.ram_top, None, None)
        self.reads = 0
        self.refused = 0
        self.failed = 0

    def ok(self, pa, n):
        if not isinstance(pa, int) or not isinstance(n, int) or n <= 0:
            return False
        for lo, hi in self.ranges:
            if lo <= pa and pa + n <= hi:
                return True
        return False

    def read(self, pa, n, tries=2):
        if not self.ok(pa, n):
            self.refused += 1
            return None
        self.reads += 1
        try:
            b = self.dl.retry_phys(self.g, pa, n, tries=tries)
        except OSError:
            self.failed += 1
            return None
        if not b or len(b) != n:
            self.failed += 1
            return None
        return b

    def alive(self):
        try:
            return self.dl.find_pid()
        except OSError:
            return None

    def close(self):
        try:
            self.g.close()
        except Exception:                        # noqa: BLE001
            pass


# ---------------------------------------------------------------------------
# maths: world -> pixel (column convention, w = depth; the pair _mk20 pinned)
# ---------------------------------------------------------------------------
def project(m, x, y, z, w, h):
    """(sx, sy, depth) or None when the point is behind the eye."""
    px = m[0] * x + m[4] * y + m[8] * z + m[12]
    py = m[1] * x + m[5] * y + m[9] * z + m[13]
    pw = m[3] * x + m[7] * y + m[11] * z + m[15]
    if not all(math.isfinite(c) for c in (px, py, pw)) or pw <= 1e-6:
        return None
    sx = (px / pw * 0.5 + 0.5) * w
    sy = (0.5 - py / pw * 0.5) * h
    if not all(math.isfinite(c) for c in (sx, sy)):
        return None
    return sx, sy, pw


def decode_position(b, indices=SEED_TRIPLE, layout=None, require_component=False,
                    max_abs=40000.0):
    """Decode a declared triple without guessing its meaning.

    The old caller rounded every alternate component to zero; it also silently
    accepted quaternions.  Neither behaviour is used by live rendering now.
    ``layout`` is descriptive provenance, never a player-type assertion.
    """
    indices = tuple(indices)
    if layout == "utf16":
        if not b or len(indices) != 2:
            return None
        first, end = indices
        if first < 0 or end <= first or end * 2 > len(b):
            return None
        try:
            text = b[first * 2:end * 2].decode("utf-16-le", errors="strict")
        except UnicodeError:
            return None
        return text or None
    if not b or len(indices) != 3 or any(i < 0 for i in indices):
        return None
    if len(b) < (max(indices) + 1) * 4:
        return None
    # Numeric offsets identify separate float words, not a packed triple at zero.
    v = tuple(struct.unpack_from("<f", b, i * 4)[0] for i in indices)
    if any(not math.isfinite(x) or abs(x) > max_abs for x in v):
        return None
    if all(abs(x) < 1e-6 for x in v):
        return None
    if require_component:
        if layout not in (None, "component3x4"):
            return None
        if len(indices) == 2:
            return None
        if not component_clone_ok(b, indices):
            return None
    return v


def component_clone_ok(b, indices=COMPONENT_TRIPLE):
    """The duplicate is evidence of a component, NOT of a human/player object."""
    if not b or len(b) < 0xB4:
        return False
    f = struct.unpack_from("<45f", b, 0)
    for i in indices:
        if i + 12 >= len(f) or abs(f[i] - f[i + 12]) > 0.1:
            return False
    if set(indices) >= {0, 16, 32}:
        for i in (3, 11, 15):
            if abs(f[i]) > 1e-4:
                return False
        for i in (5, 6):
            if abs(f[i]) > 1e-4:
                return False
    return True


def seed_triple(b, indices=SEED_TRIPLE, require_component=False):
    """Backwards-compatible, lossless decoder; semantic checks are separate."""
    return decode_position(b, indices, require_component=require_component)


def record_is_void(v):
    """True when a decoded record matches the PROVEN death signature: a census
    address that dies at a match boundary reads back as all zeros (FACTS 09/11,
    temp/_mk20_slots.txt).  Empty strings are void too (utf16 lane); any other
    shape is left to the decoder/structural checks."""
    if v is None:
        return True
    if isinstance(v, str):
        return v == ""
    if isinstance(v, (tuple, list)):
        try:
            return all(float(c) == 0.0 for c in v)
        except (TypeError, ValueError):
            return False
    return False


def _empty_stats():
    return {"candidates": 0, "visible": 0, "behind": 0, "bad_head": 0,
            "bad_size": 0, "offscreen": 0, "clipped": 0, "invalid": 0}


def project_entities(m, ents, w, h, carry=None):
    """Return (drawable boxes, terminal per-record rejection counters).

    A valid record contributes to exactly one bucket.  Offscreen projections
    never become render candidates; partial intersections are clipped and
    explicitly counted.  Invalid window dimensions are a hard precondition.
    """
    stats = _empty_stats()
    res = []
    if not matrix_plausible(m) or w < MIN_CLIENT_W or h < MIN_CLIENT_H:
        raise ValueError("a plausible matrix and validated %dx%d client area are required" %
                         (MIN_CLIENT_W, MIN_CLIENT_H))
    for pa, v in ents:
        stats["candidates"] += 1
        try:
            x, y, z = (float(v[0]), float(v[1]), float(v[2]))
            if not all(math.isfinite(c) for c in (x, y, z)):
                stats["invalid"] += 1
                continue
            feet = project(m, x, y, z, w, h)
            if feet is None:
                stats["behind"] += 1
                continue
            head = project(m, x, y, z + HEAD_Z, w, h)
            if head is None:
                stats["bad_head"] += 1
                continue
            y1, y0 = feet[1], head[1]
            bh = y1 - y0
            if not math.isfinite(bh) or bh < 4.0 or bh > 2.0 * h:
                stats["bad_size"] += 1
                continue
            bw = min(bh * BOX_W, BOX_MAX_W)
            cx = (feet[0] + head[0]) * 0.5
            left, right = cx - bw * 0.5, cx + bw * 0.5
            if right < 0 or left > w or y1 < 0 or y0 > h:
                stats["offscreen"] += 1
                continue
            clipped = left < 0 or right > w or y0 < 0 or y1 > h
            if clipped:
                stats["clipped"] += 1
            if carry is not None:
                carry.append(pa)  # box[<n>] <-> carry[n] alignment for labels
            res.append((max(0.0, left), max(0.0, y0), min(float(w), right),
                        min(float(h), y1), feet[2]))
            stats["visible"] += 1
        except (TypeError, ValueError, OverflowError, IndexError):
            stats["invalid"] += 1
    return res, stats


def boxes_for(m, ents, w, h):
    """Compatibility wrapper: only boxes intersecting the game client area."""
    return project_entities(m, ents, w, h)[0]


def matrix_plausible(m):
    """Cheap structural gate before any projection work.

    A live view-projection never contains NaN/inf, never has a degenerate
    3x3 rotation/projection block, and never has a row of that block with a
    length outside sane float range.  This does not *prove* the matrix is the
    camera; it only stops obviously torn/garbage windows from being scored and
    drawn as if they were the world.
    """
    if not m or len(m) != 16:
        return False
    for v in m:
        if v != v or abs(v) > 1.0e6:
            return False
    a, b, c = m[0], m[1], m[2]
    d, e, f = m[4], m[5], m[6]
    g, h, i = m[8], m[9], m[10]
    det = (a * (e * i - f * h)
           - b * (d * i - f * g)
           + c * (d * h - e * g))
    if det != det or abs(det) < 1.0e-7:
        return False
    for row in ((a, b, c), (d, e, f), (g, h, i)):
        n = math.sqrt(row[0] * row[0] + row[1] * row[1] + row[2] * row[2])
        if n != n or not (1.0e-3 < n < 1.0e3):
            return False
    return True


# ---------------------------------------------------------------------------
# M2 field bindings: declared, bounded, additive; never guessed
# ---------------------------------------------------------------------------
FIELD_FMTS = {"i32": ("<i", 4), "u32": ("<I", 4),
              "f32": ("<f", 4), "u8": ("<B", 1)}
META_STR_MAX = 64             # longest single str-u16le field worth reading
META_SPAN_CAP = 0x8000        # one-ioctl union ceiling; wider tables walk clusters
META_CLUSTER_GAP = 0x40       # declared holes smaller than this merge into one span
MAX_FIELDS_PER_RECORD = 24
FIELD_WARNED = set()


def _warn_field(msg):
    """Malformed field rows degrade, never die; one log line per message."""
    if msg not in FIELD_WARNED:
        FIELD_WARNED.add(msg)
        try:
            with open(os.path.join(TMP, "qk_field_warn.txt"), "a",
                      encoding="utf-8") as f:
                f.write("%s %s\n" % (now(), msg))
        except OSError:
            pass


def parse_field_specs(rec):
    """census record -> tuple of (name, offset, size, fmt), offset-sorted.

    Rows are refused (skipped + warned) unless: non-empty name, offset >= 0,
    size > 0, fmt in FIELD_FMTS, or 'str-u16le' with an even size within
    META_STR_MAX*2.  Scalar sizes coerce to the format's natural width so a
    typo'd size cannot widen a read past the declared cell."""
    decls = rec.get("fields") if isinstance(rec, dict) else None
    if not isinstance(decls, (list, tuple)):
        return ()
    specs = []
    for d in decls[:24]:
        try:
            name = str(d["name"])
            off = int(d["offset"])
            size = int(d["size"])
            fmt = str(d.get("fmt", "i32"))
        except (KeyError, TypeError, ValueError, IndexError):
            continue
        if not name or off < 0 or size <= 0:
            _warn_field("refused %r off=%r size=%r" % (name, off, size))
            continue
        if fmt == "str-u16le":
            if size % 2 or size > META_STR_MAX * 2:
                _warn_field("refused %r bad u16le size %d" % (name, size))
                continue
        elif fmt in FIELD_FMTS:
            size = FIELD_FMTS[fmt][1]
        else:
            _warn_field("refused %r unknown fmt %r" % (name, fmt))
            continue
        specs.append((name, off, size, fmt))
    return tuple(sorted(set(specs), key=lambda s: (s[1], s[0])))


def decode_field(buf, spec, shift=0):
    """One declared spec -> decoded value, or None; never raises.

    shift moves the spec's offset inside buf (cluster buffers subtract their
    span base).  A short/malformed buffer degrades only that field -- sibling
    fields in the same buffer still decode."""
    _name, fo, size, fmt = spec
    fo += shift
    if fo < 0 or fo + size > len(buf):
        return None
    try:
        if fmt == "str-u16le":
            return decode_position(bytes(buf[fo:fo + size]),
                                   (0, size // 2), "utf16")
        return struct.unpack_from(FIELD_FMTS[fmt][0], buf, fo)[0]
    except struct.error:
        return None


def field_plan(specs):
    """specs -> (union_span, cluster_spans), record-relative byte ranges.

    union is (lo, hi) of every declared cell when hi-lo <= META_SPAN_CAP,
    else None (too wide for one ioctl).  clusters merge cells separated by
    < META_CLUSTER_GAP so one read usually gathers several neighbours."""
    if not specs:
        return None, ()
    cells = sorted((s[1], s[1] + s[2]) for s in specs)
    lo, hi = cells[0][0], max(end for _, end in cells)
    union = (lo, hi) if hi - lo <= META_SPAN_CAP else None
    runs = []
    cur_lo, cur_hi = cells[0]
    for c_lo, c_hi in cells[1:]:
        if c_lo - cur_hi < META_CLUSTER_GAP:
            cur_hi = max(cur_hi, c_hi)
        else:
            runs.append((cur_lo, cur_hi))
            cur_lo, cur_hi = c_lo, c_hi
    runs.append((cur_lo, cur_hi))
    return union, tuple(runs)


def read_meta(sess, pa):
    """Declared-field fetch for one entity; counters stay orthogonal to M1.

    Stage 1 is the union span (one physical read); stage 2 repairs whatever
    the union missed -- holes, cap refusals, torn tails -- with per-cluster
    reads, so a hostile address space degrades to partial, not empty.
    Nothing here feeds the M1 zero-ledger; stale-key eviction is tick()'s."""
    specs = sess._field_specs.get(pa)
    plan = sess._field_plans.get(pa)
    if not specs or sess.no_fields:
        return None
    union, clusters = plan
    got = {}

    def drain(buf, group, base):
        for spec in group:
            v = decode_field(buf, spec, -base)
            if v is not None:
                got[spec[0]] = v

    if union is not None:
        buf = sess.ph.read(pa + union[0], union[1] - union[0])
        sess.field_reads += 1
        if buf is not None:
            drain(buf, specs, union[0])
    if len(got) < len(specs):
        # union absent OR refused/incomplete: repair per-cluster for the gaps
        for run in clusters:
            missing = [s for s in specs
                       if s[0] not in got and run[0] <= s[1] < run[1]]
            if not missing:
                continue
            buf = sess.ph.read(pa + run[0], run[1] - run[0])
            sess.field_reads += 1
            if buf is None:
                continue
            drain(buf, missing, run[0])
            if len(got) == len(specs):
                break
    if not got:
        sess.field_failures += 1
        return {}
    if len(got) < len(specs):
        sess.field_partial += 1
    return got


BLEEDOUT_NAMES = {0: "up", 1: "down", 2: "dead"}
LABEL_CHARS_MAX = 96


def compose_labels(meta_by_pa, local_team=None):
    """entity PA -> one short on-box label; absent/garbage fields vanish."""
    texts = {}
    for pa, meta in meta_by_pa.items():
        bits = []
        hp, mx = meta.get("hp"), meta.get("max_hp")
        if isinstance(hp, int):
            bits.append("%d/%d" % (hp, mx)
                        if isinstance(mx, int) and 0 < mx and hp != mx
                        else str(hp))
        shield_sum = sum(v for k in ("shield", "temp_shield", "extra_shield")
                         if isinstance(v := meta.get(k), int))
        if shield_sum:
            bit = "s%d" % shield_sum
            tier = meta.get("extra_tier")
            if isinstance(tier, int):
                bit += "t%d" % tier
            bits.append(bit)
        team = meta.get("team")
        if isinstance(team, int) and local_team is not None and team != local_team:
            bits.append("T%d" % team)
        bleed = meta.get("bleed")
        if bleed == 1:
            bits.append("DBNO")
        if meta.get("life") == 1:
            bits.append("dead")
        name = meta.get("name")
        if name:
            name = str(name).split("\x00")[0].strip()
            if name:
                bits.append(name[:32])
        if bits:
            texts[pa] = " | ".join(bits)[:LABEL_CHARS_MAX]
    return texts


def score_vp(m, ents, w, h):
    """Exactly the number of records whose matching box can be drawn."""
    return project_entities(m, ents, w, h)[1]["visible"]


def pick_window(ph, base, rva, ents, w, h, wide=False):
    """(matrix, lead, hits, rva) -- the 16-float window at this address that
    projects the census onto the screen.  0x9440B4 vs 0x9440B0 was never resolved
    by hand; the scoring decides it, and 'wide' widens the ADDRESS (matrix copies
    sit 0xE0 apart) instead of the guess."""
    leads = (0, 4)
    rvas = [rva]
    if wide:
        rvas = [rva + d for d in range(-0x1000, 0x1001, 0x10)]
    best = (None, 0, -1, rva)
    for r in rvas:
        b = ph.read(base + r, 0x80, tries=2)
        if not b:
            continue
        for lead in leads:
            m = struct.unpack_from("<16f", b, lead)
            if not matrix_plausible(m):
                continue
            hits = score_vp(m, ents, w, h)
            if hits > best[2]:
                best = (m, lead, hits, r)
    return best


# ---------------------------------------------------------------------------
# the window: layered + colorkey + click-through + noactivate
# ---------------------------------------------------------------------------
user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

LRESULT = ctypes.c_ssize_t
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM)

WS_POPUP = 0x80000000
WS_EX_LAYERED = 0x00080000
WS_EX_TRANSPARENT = 0x00000020
WS_EX_TOPMOST = 0x00000008
WS_EX_TOOLWINDOW = 0x00000080
WS_EX_NOACTIVATE = 0x08000000
LWA_COLORKEY = 0x00000001
SW_SHOWNOACTIVATE = 4
HWND_TOPMOST = wt.HWND(-1)
SWP_NOMOVE = 0x0002
SWP_NOSIZE = 0x0001
SWP_NOACTIVATE = 0x0010
DT_LEFT = 0x0000
DT_SINGLELINE = 0x0020
DT_NOPREFIX = 0x0800
DT_VCENTER = 0x0004
TRANSPARENT_BK = 1
PM_REMOVE = 0x0001
SRCCOPY = 0x00CC0020
WM_PAINT = 0x000F
WM_DESTROY = 0x0002
WM_ERASEBKGND = 0x0014


class WNDCLASSEXW(ctypes.Structure):
    _fields_ = [("cbSize", wt.UINT), ("style", wt.UINT), ("lpfnWndProc", WNDPROC),
                ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
                ("hInstance", wt.HINSTANCE), ("hIcon", wt.HICON),
                ("hCursor", wt.HANDLE), ("hbrBackground", wt.HBRUSH),
                ("lpszMenuName", wt.LPCWSTR), ("lpszClassName", wt.LPCWSTR),
                ("hIconSm", wt.HICON)]


user32.DefWindowProcW.restype = LRESULT
user32.DefWindowProcW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
user32.CreateWindowExW.restype = wt.HWND
user32.CreateWindowExW.argtypes = [wt.DWORD, wt.LPCWSTR, wt.LPCWSTR, wt.DWORD,
                                   ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                   wt.HWND, wt.HMENU, wt.HINSTANCE, wt.LPVOID]
user32.RegisterClassExW.restype = wt.ATOM
user32.RegisterClassExW.argtypes = [ctypes.POINTER(WNDCLASSEXW)]
user32.SetLayeredWindowAttributes.argtypes = [wt.HWND, wt.DWORD, wt.BYTE, wt.DWORD]
user32.GetDC.restype = wt.HDC
user32.GetDC.argtypes = [wt.HWND]
user32.ReleaseDC.argtypes = [wt.HWND, wt.HDC]
user32.ValidateRect.restype = wt.BOOL
user32.ValidateRect.argtypes = [wt.HWND, wt.LPVOID]
user32.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int,
                                 ctypes.c_int, ctypes.c_int, wt.UINT]
user32.GetAsyncKeyState.restype = ctypes.c_short
user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
user32.PeekMessageW.argtypes = [ctypes.POINTER(wt.MSG), wt.HWND, wt.UINT, wt.UINT, wt.UINT]

gdi32.CreateCompatibleDC.restype = wt.HDC
gdi32.CreateCompatibleDC.argtypes = [wt.HDC]
gdi32.CreateCompatibleBitmap.restype = wt.HBITMAP
gdi32.CreateCompatibleBitmap.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int]
gdi32.SelectObject.restype = wt.HGDIOBJ
gdi32.SelectObject.argtypes = [wt.HDC, wt.HGDIOBJ]
gdi32.CreateSolidBrush.restype = wt.HBRUSH
gdi32.CreateSolidBrush.argtypes = [wt.DWORD]
gdi32.CreateFontW.restype = wt.HFONT
gdi32.CreateFontW.argtypes = [ctypes.c_int] * 5 + [wt.DWORD] * 8 + [wt.LPCWSTR]
gdi32.SetBkMode.argtypes = [wt.HDC, ctypes.c_int]
gdi32.SetTextColor.argtypes = [wt.HDC, wt.DWORD]
gdi32.DeleteObject.argtypes = [wt.HGDIOBJ]
gdi32.DeleteObject.restype = wt.BOOL
gdi32.DeleteDC.argtypes = [wt.HDC]
gdi32.DeleteDC.restype = wt.BOOL
user32.DestroyWindow.argtypes = [wt.HWND]
user32.DestroyWindow.restype = wt.BOOL
user32.IsWindow.argtypes = [wt.HWND]
user32.GetForegroundWindow.restype = wt.HWND
user32.DrawTextW.argtypes = [wt.HDC, wt.LPCWSTR, ctypes.c_int, wt.LPVOID, wt.UINT]
gdi32.BitBlt.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                         wt.HDC, ctypes.c_int, ctypes.c_int, wt.DWORD]
user32.FillRect.argtypes = [wt.HDC, wt.LPVOID, wt.HBRUSH]


class Overlay(object):
    """A GDI canvas on a colour-keyed layered window.  Pure black is transparent,
    so every frame starts by filling black and only lit pixels survive the blit."""

    def __init__(self, rect):
        self.hwnd = self.dc = self.bmp = self._screen = None
        self.brush = {}
        self.font = self.font_sm = self._old = self._old_font = None
        self.w = self.h = 1
        self.rect = tuple(rect)
        try:
            self._initialize(rect)
        except BaseException:
            self.close()
            raise

    def _initialize(self, rect):
        self.rect = tuple(rect)
        self.w = max(1, rect[2] - rect[0])
        self.h = max(1, rect[3] - rect[1])
        self.hwnd = None
        self._proc = WNDPROC(self._wndproc)          # lifetime: keep the thunk
        hinst = kernel32.GetModuleHandleW(None)
        wc = WNDCLASSEXW()
        wc.cbSize = ctypes.sizeof(WNDCLASSEXW)
        wc.lpfnWndProc = self._proc
        wc.hInstance = hinst
        wc.lpszClassName = "QkLiveOverlay"
        user32.RegisterClassExW(ctypes.byref(wc))    # already registered is fine
        ex = (WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST
              | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE)
        self.hwnd = user32.CreateWindowExW(ex, "QkLiveOverlay", "qk_live", WS_POPUP,
                                           rect[0], rect[1], self.w, self.h,
                                           None, None, hinst, None)
        if not self.hwnd:
            raise OSError("CreateWindowExW failed (%d)" % ctypes.get_last_error())
        user32.SetLayeredWindowAttributes(self.hwnd, KEY_BLACK, 0, LWA_COLORKEY)
        user32.ShowWindow(self.hwnd, SW_SHOWNOACTIVATE)
        user32.SetWindowPos(self.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        self._screen = user32.GetDC(None)
        self.dc = gdi32.CreateCompatibleDC(self._screen)
        self.bmp = gdi32.CreateCompatibleBitmap(self._screen, self.w, self.h)
        self._old = gdi32.SelectObject(self.dc, self.bmp)
        self.brush = {}
        self.font = gdi32.CreateFontW(-15, 0, 0, 0, 600, 0, 0, 0, 1, 4, 0, 5, 0, "Consolas")
        self._old_font = gdi32.SelectObject(self.dc, self.font)
        self.capture_policy = "normal (captured)"
        self.font_sm = gdi32.CreateFontW(-13, 0, 0, 0, 500, 0, 0, 0, 1, 4, 0, 5, 0, "Consolas")
        gdi32.SetBkMode(self.dc, TRANSPARENT_BK)

    def set_stream_safe(self, enabled):
        """Opt-in OBS exclusion; never claim that this hides us from anti-cheat."""
        if not enabled:
            return
        fn = getattr(user32, "SetWindowDisplayAffinity", None)
        if fn is None:
            self.capture_policy = "normal (display-affinity unavailable)"
            return
        fn.argtypes = [wt.HWND, wt.DWORD]
        fn.restype = wt.BOOL
        ctypes.set_last_error(0)
        if fn(self.hwnd, 0x11):  # WDA_EXCLUDEFROMCAPTURE, readable Windows 10 2004+
            self.capture_policy = "capture-excluded (stream-only)"
        else:
            self.capture_policy = ("normal (affinity error %d)" % ctypes.get_last_error())

    def resize(self, rect):
        self.w = max(1, rect[2] - rect[0])
        self.h = max(1, rect[3] - rect[1])
        self.rect = tuple(rect)
        gdi32.SelectObject(self.dc, self._old)
        gdi32.DeleteObject(self.bmp)
        self.bmp = gdi32.CreateCompatibleBitmap(self._screen, self.w, self.h)
        self._old = gdi32.SelectObject(self.dc, self.bmp)
        gdi32.SelectObject(self.dc, self.font_sm)
        user32.SetWindowPos(self.hwnd, HWND_TOPMOST, rect[0], rect[1], self.w, self.h,
                            SWP_NOACTIVATE)
        if not self.bmp:
            raise OSError("CreateCompatibleBitmap failed (%d)" % ctypes.get_last_error())

    def _brush(self, color):
        b = self.brush.get(color)
        if b is None:
            b = gdi32.CreateSolidBrush(color)
            self.brush[color] = b
        return b

    def _wndproc(self, hwnd, msg, wp, lp):
        if msg == WM_ERASEBKGND:
            return 1
        if msg == WM_PAINT:
            # Validate the update region; otherwise WM_PAINT is posted forever
            # and pump() starves the frame loop.
            user32.ValidateRect(hwnd, None)
            return 0
        if msg == WM_DESTROY:
            user32.PostQuitMessage(0)
            return 0
        return user32.DefWindowProcW(hwnd, msg, wp, lp)

    # -- drawing -----------------------------------------------------------
    def clear(self):
        r = wt.RECT(0, 0, self.w, self.h)
        user32.FillRect(self.dc, ctypes.byref(r), self._brush(KEY_BLACK))

    def fill(self, x0, y0, x1, y1, color):
        user32.FillRect(self.dc, ctypes.byref(wt.RECT(int(x0), int(y0), int(x1), int(y1))),
                        self._brush(color))

    def frame(self, x0, y0, x1, y1, color, thick=1):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        b = self._brush(color)
        for i in range(max(1, int(thick))):
            l, t, r, bt = x0 - i, y0 - i, x1 + i + 1, y1 + i + 1
            for rect in (wt.RECT(l, t, r, t + 1), wt.RECT(l, bt - 1, r, bt),
                         wt.RECT(l, t, l + 1, bt), wt.RECT(r - 1, t, r, bt)):
                user32.FillRect(self.dc, ctypes.byref(rect), b)

    def text(self, x, y, s, color, small=False, width=600):
        gdi32.SelectObject(self.dc, self.font_sm if small else self.font)
        gdi32.SetTextColor(self.dc, color)
        r = wt.RECT(int(x), int(y), int(x) + int(width), int(y) + 20)
        user32.DrawTextW(self.dc, s, -1, ctypes.byref(r),
                         DT_LEFT | DT_SINGLELINE | DT_NOPREFIX | DT_VCENTER)

    def present(self):
        dc = user32.GetDC(self.hwnd)
        if dc:
            copied = bool(gdi32.BitBlt(dc, 0, 0, self.w, self.h, self.dc, 0, 0, SRCCOPY))
            user32.ReleaseDC(self.hwnd, dc)
        else:
            copied = False
        user32.SetWindowPos(self.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        return copied

    def pump(self):
        msg = wt.MSG()
        while user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, PM_REMOVE):
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

    def close(self):
        if self.hwnd:
            user32.ShowWindow(self.hwnd, 0)  # SW_HIDE
            user32.SetLayeredWindowAttributes(self.hwnd, 0, 0, 0)
            user32.DestroyWindow(self.hwnd)
            self.hwnd = None
        if getattr(self, "dc", None):
            gdi32.SelectObject(self.dc, getattr(self, "_old", None))
            gdi32.SelectObject(self.dc, getattr(self, "_old_font", 0))
        if getattr(self, "bmp", None):
            gdi32.DeleteObject(self.bmp)
            self.bmp = None
        for font in ("font", "font_sm"):
            obj = getattr(self, font, None)
            if obj:
                gdi32.DeleteObject(obj)
                setattr(self, font, None)
        for b in getattr(self, "brush", {}).values():
            gdi32.DeleteObject(b)
        self.brush = {}
        if getattr(self, "dc", None):
            gdi32.DeleteDC(self.dc)
            self.dc = None
        if getattr(self, "_screen", None):
            user32.ReleaseDC(None, self._screen)
            self._screen = None


# ---------------------------------------------------------------------------
# menu state: toggles, hotkeys, and a file so a restart keeps them
# ---------------------------------------------------------------------------
DEFAULTS = {
    "menu": 1, "esp": 1, "filled": 0, "glow": 1, "dist": 1,
    "thick": 2, "scheme": 0, "hz": 20,
}
def sanitize_config(cfg):
    out_cfg = dict(DEFAULTS)
    for key in ("menu", "esp", "filled", "glow", "dist"):
        try:
            out_cfg[key] = 1 if int(cfg.get(key, out_cfg[key])) else 0
        except (TypeError, ValueError):
            pass
    try:
        out_cfg["thick"] = int(cfg.get("thick", out_cfg["thick"]))
    except (TypeError, ValueError):
        out_cfg["thick"] = DEFAULTS["thick"]
    try:
        out_cfg["scheme"] = int(cfg.get("scheme", 0))
    except (TypeError, ValueError):
        out_cfg["scheme"] = 0
    try:
        out_cfg["hz"] = int(cfg.get("hz", DEFAULTS["hz"]))
    except (TypeError, ValueError):
        out_cfg["hz"] = DEFAULTS["hz"]
    out_cfg["thick"] = min(4, max(1, out_cfg["thick"]))
    out_cfg["scheme"] %= len(SCHEMES)
    if out_cfg["hz"] not in (10, 20, 30, 60, 120, 144):
        out_cfg["hz"] = DEFAULTS["hz"]
    return out_cfg


KEYS = (
    (0x2D, "INSERT", "menu", "menu"),
    (0x70, "F1", "esp", "esp"),
    (0x71, "F2", "filled", "fill"),
    (0x72, "F3", "glow", "glow"),
    (0x73, "F4", "dist", "dist"),
    (0x74, "F5", "thick", "thick"),
    (0x75, "F6", "scheme", "colour"),
    (0x76, "F7", "hz", "rate"),
)
VK_END = 0x23
VK_F8 = 0x77


def cfg_load(path=CFG):
    cfg = dict(DEFAULTS)
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip()
                    if k in cfg:
                        try:
                            cfg[k] = int(v.strip(), 0)
                        except ValueError:
                            pass
    except OSError:
        pass
    return sanitize_config(cfg)


def cfg_save(cfg, path=CFG):
    try:
        with open(path, "w", encoding="utf-8") as f:
            for k in sorted(cfg):
                f.write("%s=%d\n" % (k, cfg[k]))
        return True
    except OSError:
        return False


class Keys(object):
    """Edge detection over GetAsyncKeyState: the overlay never takes focus, so this
    is the only way the menu can be driven while the game owns the keyboard."""

    def __init__(self):
        self.prev = {}

    def hit(self, vk):
        st = user32.GetAsyncKeyState(vk) & 0x8000
        was = self.prev.get(vk, False)
        self.prev[vk] = bool(st)
        return bool(st) and not was


def apply_key(cfg, action):
    """One hotkey -> one variable.  Returns the (key, value) that moved, or None."""
    if action == "thick":
        cfg["thick"] = cfg["thick"] % 4 + 1
        return ("thick", cfg["thick"])
    if action == "scheme":
        cfg["scheme"] = (cfg["scheme"] + 1) % len(SCHEMES)
        return ("scheme", SCHEMES[cfg["scheme"]][0])
    if action == "hz":
        order = (10, 20, 30, 60, 120, 144)
        i = order.index(cfg["hz"]) if cfg["hz"] in order else 1
        cfg["hz"] = order[(i + 1) % len(order)]
        return ("hz", cfg["hz"])
    cfg[action] = 0 if cfg.get(action) else 1
    return (action, "on" if cfg[action] else "off")


def menu_rows(cfg):
    return [
        ("INSERT", "menu", "shown" if cfg["menu"] else "hidden"),
        ("F1", "esp", "on" if cfg["esp"] else "off"),
        ("F2", "fill", "on" if cfg["filled"] else "off"),
        ("F3", "glow", "on" if cfg["glow"] else "off"),
        ("F4", "dist", "on" if cfg["dist"] else "off"),
        ("F5", "thick", "%dx" % cfg["thick"]),
        ("F6", "colour", SCHEMES[cfg["scheme"] % len(SCHEMES)][0]),
        ("F7", "rate", "%d Hz" % cfg["hz"]),
        ("F8", "save", CFG.split(os.sep)[-1]),
        ("END", "quit", ""),
    ]


def draw_menu(ov, cfg, st, accent):
    rows = menu_rows(cfg)
    x, y, w = 24, 24, 300
    h = 34 + 20 * len(rows) + 10
    ov.fill(x, y, x + w, y + h, 0x00181818)
    ov.frame(x, y, x + w, y + h, accent, 1)
    ov.fill(x, y, x + w, y + 3, accent)
    ov.text(x + 12, y + 8, "QwenKern  range ESP", 0x00E8E8E8)
    ry = y + 34
    for key, label, val in rows:
        on = val in ("on", "shown") or val.endswith("x") or val.endswith("Hz")
        ov.text(x + 12, ry, key, 0x00909090, small=True)
        ov.text(x + 92, ry, label, 0x00D0D0D0, small=True)
        ov.text(x + 190, ry, val, accent if on else 0x00707070, small=True)
        ry += 20
    if st:
        ov.text(x + 12, y + h - 18, st, 0x00808080, small=True)


def draw_status(ov, text, accent):
    ov.text(24, ov.h - 30, text, accent, small=True)


def pipeline_summary(sess):
    if sess is None:
        return "SIMULATION - no game data"
    src = sess.source or {}
    p = sess.projection
    short = {"player_type_unverified": "NO VERIFIED PLAYERS",
             "stale": "STALE SOURCE", "pid_mismatch": "PID MISMATCH",
             "owner_class_unverified": "OWNER/CLASS UNBOUND",
             "candidate_eligible": "VALIDATED PLAYER CANDIDATES"}
    gate = short.get(src.get("gate"), "SOURCE: %s" % src.get("gate", "NONE"))
    extra = " ROUND?" if getattr(sess, "round_transition", False) else ""
    nfld = len(getattr(sess, "meta", None) or {})
    if nfld:
        extra += " | fld %d" % nfld
    return ("cand %d | remote %d | boxes %d | off %d behind %d | "
            "unverified %d | local %d | readerr %d | budget %d | exp %d%s | %s"
            % (sess.seed_total, len(sess.ents), len(sess.boxes), p.get("offscreen", 0),
               p.get("behind", 0), sess.skipped_unverified, sess.local_excluded,
               sess.read_failures, sess.budget_excluded,
               getattr(sess, "expired_events", 0), extra, gate))


def live_verdict(sess, game_alive, client_valid, render_observed=False):
    """A tick-quality verdict -- explicitly not a match-completeness assertion."""
    if not game_alive or not client_valid:
        return 3, "PARTIAL (SKIPPED rendering, R9)"
    if not render_observed:
        return 4, "PARTIAL (SKIPPED in-game rendering; projection alone is not a pixel verdict)"
    if not sess or not sess.allowed_to_draw or sess.source.get("gate") != "candidate_eligible":
        return 4, "PARTIAL - discovery did not establish verified player candidates"
    if not sess.ents or not sess.boxes:
        return 4, "PARTIAL - validated candidates, zero drawable records"
    if sum(sess.projection.get(k, 0) for k in ("visible", "behind", "bad_head",
                                               "bad_size", "offscreen", "invalid")) \
            != sess.projection.get("candidates", -1):
        return 4, "FAIL - per-record projection accounting is inconsistent"
    return 0, "PASS (%d player-bound candidate boxes)" % len(sess.boxes)


# ---------------------------------------------------------------------------
# the game window: project into its client area, not into "the screen"
# ---------------------------------------------------------------------------
user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
user32.IsWindowVisible.argtypes = [wt.HWND]
user32.GetClientRect.argtypes = [wt.HWND, wt.LPVOID]
user32.ClientToScreen.argtypes = [wt.HWND, wt.LPVOID]
user32.EnumWindows.argtypes = [ctypes.c_void_p, wt.LPARAM]
user32.GetSystemMetrics.argtypes = [ctypes.c_int]
user32.GetSystemMetrics.restype = ctypes.c_int
kernel32.GetModuleHandleW.restype = wt.HINSTANCE

_ENUMPROC = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)


def game_rect(pid):
    """(x, y, x+w, y+h) of the game's biggest visible window, or None."""
    best = [None, 0]

    def cb(hwnd, lp):
        p = wt.DWORD(0)
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value != pid:
            return True
        if not user32.IsWindowVisible(hwnd):
            return True
        r = wt.RECT()
        if not user32.GetClientRect(hwnd, ctypes.byref(r)):
            return True
        w, h = r.right - r.left, r.bottom - r.top
        if w < 320 or h < 200:
            return True
        if w * h > best[1]:
            pt = wt.POINT(0, 0)
            user32.ClientToScreen(hwnd, ctypes.byref(pt))
            best[0] = (pt.x, pt.y, pt.x + w, pt.y + h)
            best[1] = w * h
        return True

    user32.EnumWindows(_ENUMPROC(cb), 0)
    return best[0]


def screen_rect():
    return (0, 0, user32.GetSystemMetrics(0), user32.GetSystemMetrics(1))


def valid_client(rect):
    return bool(rect and len(rect) == 4 and rect[2] - rect[0] >= MIN_CLIENT_W
                and rect[3] - rect[1] >= MIN_CLIENT_H)


def foreground_pid():
    hwnd = user32.GetForegroundWindow()
    if not hwnd:
        return None
    pid = wt.DWORD(0)
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value or None


# ---------------------------------------------------------------------------
# the live feed: matrix and records read in the same tick
# ---------------------------------------------------------------------------
class Session(object):
    def __init__(self, cap=0, wide=False, base=None, rva=None,
                 census_path=None, max_age=900.0, allow_unverified=False,
                 refresh_seconds=None, expiry_zeros=None, no_fields=False):
        self.ph = Phys()
        self.pid = self.ph.alive()
        off = offsets_file()
        self.base = base if base is not None else (
            int(off["image_pa"], 16) if "image_pa" in off else None)
        self.rva = rva if rva is not None else int(off.get("vp_rva", "0x9440B4"), 16)
        self.wide = wide
        self.wide_rva = None
        self.m = None
        self.lead = 0
        self.hits = 0
        self.boxes = []
        self.ents = []
        self.cap = cap
        self.seed_total = 0
        self.dropped = 0
        self.read_failures = 0
        self.local_excluded = 0
        self.budget_excluded = 0
        self.skipped_unverified = 0
        self.projection = _empty_stats()
        self.provenance_lost = False
        self.census_path = os.path.abspath(census_path or arg("census", CENSUS))
        self.max_age = arg("max-age", 900.0, float) if max_age is None else max_age
        self.allow_unverified = allow_unverified
        self.refresh_seconds = max(0.5, float(arg("refresh", 10.0, float)
                                      if refresh_seconds is None else refresh_seconds))
        self.next_refresh = 0.0
        self.source = None
        self._specs = {}
        self.allowed_to_draw = False
        self.expiry_zeros = max(0, int(arg("expiry-zeros", DEFAULT_EXPIRY_ZEROS, int)
                                      if expiry_zeros is None else expiry_zeros))
        self.zero_streaks = {}
        self.expired = set()
        self.expired_events = 0
        self.round_transition = False
        # M2 field bindings: declared-cell reads + labels, orthogonally counted
        self.no_fields = bool(no_fields)
        self.meta = {}            # pa -> {field-name: decoded value}
        self.labels = []          # per-drawn-box label (parallel to self.boxes)
        self.box_pas = []         # per-drawn-box owning PA (parallel to boxes)
        self.local_team = None    # provenance: local record's m_iTeamNum read
        self.field_reads = 0      # physical reads issued for declared fields
        self.field_failures = 0   # entities whose meta came back entirely empty
        self.field_partial = 0    # entities where only some declared fields landed
        self.local_meta_reads = 0 # meta reads spent on the local player's record
        self._field_specs = {}
        self._field_plans = {}
        self.generation = None

    @staticmethod
    def _generation_of(src):
        """Identity of the adopted census document; a change resets expiry state."""
        return (src.get("captured_ts"), src.get("pid"), len(src.get("records", ())))

    def _observe(self, pa, v):
        """Fold one observation (prime- or tick-cadence) into the expiry ledger.

        v is the decoded value; the PROVEN death signature (FACTS 09/11,
        temp/_mk20_slots.txt) is an all-zero payload where a live record used to
        be.  The FIRST void observation already suppresses the box (a zero
        triple decodes to world origin and drew ghost clusters after round
        transitions); K consecutive void observations (K = expiry_zeros, shared
        by both cadences, so a hz=20 tick converges in about K frames) retire
        the PA for the current generation: no further reads are spent on it and
        it cannot resurrect until the producer rewrites the census document.
        Cadence truth: strikes accumulate wherever observations happen -- tick
        supplies near-consecutive strikes while the record is on ents (the
        common mid-cycle death), but a prime-pruned corpse converges on the
        prime cadence.  Either way the first void observation suppresses the
        box, so what the user sees never waits for the counter."""
        void = record_is_void(v)
        if void:
            self.zero_streaks[pa] = self.zero_streaks.get(pa, 0) + 1
            if (self.expiry_zeros > 0
                    and self.zero_streaks[pa] >= self.expiry_zeros
                    and pa not in self.expired):
                self.expired.add(pa)
                self.expired_events += 1
            return False
        self.zero_streaks[pa] = 0
        return True

    def prime(self, now=None):
        """Refresh eligible, decoded records without semantic name guessing.

        count(player) = count(renderable spoofed/unknown objects) is not an
        acceptable implementation.  World components may be common diagnostics,
        but they don't cross the render gate until their owners establish each
        candidate's role and the local-player association.
        """
        src = read_seed_source(self.census_path, self.pid, now, self.max_age,
                               self.allow_unverified)
        self.source = src
        gen = self._generation_of(src)
        if gen != self.generation:
            self.generation = gen
            self.zero_streaks = {}
            self.expired = set()
            self.round_transition = False
            self.meta = {}
            self.local_team = None
        retired_before = self.expired_events
        healthy = 0
        self.seed_total = len(src["records"])
        self.budget_excluded = 0
        self.dropped = self.read_failures = self.local_excluded = 0
        self.skipped_unverified = (self.seed_total if not src["player_validated"] else 0)
        self.allowed_to_draw = src["gate"] == "candidate_eligible"
        self._specs = {rec["pa"]: rec for rec in src["records"]}
        self._field_specs = {}
        self._field_plans = {}
        if not self.no_fields:
            for rec in src["records"]:
                specs = parse_field_specs(rec)
                self._field_specs[rec["pa"]] = specs
                self._field_plans[rec["pa"]] = field_plan(specs)
            # one bounded meta read for the LOCAL record only: establishes
            # whose team the viewer is on (foe tagging); local draws no box.
            for rec in src["records"]:
                if rec.get("local"):
                    before = self.field_reads
                    lm = read_meta(self, rec["pa"])
                    self.local_meta_reads += self.field_reads - before
                    lt = (lm or {}).get("team")
                    if isinstance(lt, int):
                        self.local_team = lt
                    break
        keep = []
        if self.allowed_to_draw:
            for rec in src["records"]:
                if rec["role"] not in PLAYER_ROLES:
                    self.skipped_unverified += 1
                    continue
                if rec.get("local"):
                    self.local_excluded += 1
                    continue
                if rec["pa"] in self.expired:
                    continue  # retired this generation: no read, no box, no resurrect
                b = self.ph.read(rec["pa"], SEED_BYTES)
                if b is None:
                    self.read_failures += 1
                    self._observe(rec["pa"], None)
                    continue
                v = decode_position(b, rec["indices"], rec.get("layout"))
                if v is None:
                    self.dropped += 1
                    self._observe(rec["pa"], None)
                    continue
                if self._observe(rec["pa"], v):
                    keep.append((rec["pa"], v))
                    healthy += 1
        if self.cap > 0 and len(keep) > self.cap:
            self.budget_excluded = len(keep) - self.cap
            keep = keep[:self.cap]  # declared debug budget, not silent census truncation
        newly_retired = self.expired_events - retired_before
        if newly_retired >= 2:
            self.round_transition = True
        elif newly_retired == 0 and healthy:
            self.round_transition = False
        self.ents = keep
        self.boxes = []
        self.hits = 0
        self.m = None
        self.next_refresh = (time.time() if now is None else now) + self.refresh_seconds
        return keep

    def _read_vp(self, rva):
        return self.ph.read(self.base + rva, 0x80)

    def tick(self, w, h):
        stamp = time.time()
        if stamp >= self.next_refresh:
            self.prime(stamp)
        if self.base is None or not self.allowed_to_draw:
            self.boxes = []
            self.projection = _empty_stats()
            return self.boxes
        rva = self.wide_rva or self.rva
        b = self._read_vp(rva)
        best = (None, 0, -1)
        if b:
            for lead in (0, 4):
                m = struct.unpack_from("<16f", b, lead)
                if not matrix_plausible(m):
                    continue
                hits = score_vp(m, self.ents, w, h)
                if hits > best[2]:
                    best = (m, lead, hits)
        if self.wide and self.wide_rva is None and (best[0] is None or best[2] == 0):
            m, lead, hits, r = pick_window(self.ph, self.base, self.rva, self.ents,
                                           w, h, wide=True)
            if m is not None and hits > 0:
                self.wide_rva = r
                best = (m, lead, hits)
        if best[0] is not None:
            self.m, self.lead, self.hits = best
        else:
            self.m = None
            self.hits = 0
        # Invalidate, never freeze, a record whose current read failed.
        ents = []
        for pa, _old in self.ents:
            spec = self._specs.get(pa)
            raw = self.ph.read(pa, SEED_BYTES)
            v = (decode_position(raw, spec["indices"], spec.get("layout"))
                 if raw is not None and spec is not None else None)
            if v is None:
                self.read_failures += 1
                self.meta.pop(pa, None)   # dead position: no trustworthy meta
                self._observe(pa, None)
                continue
            if not self._observe(pa, v):
                self.meta.pop(pa, None)   # zero-signature corpse: drop meta
                continue  # zero-signature: boxless now; retired after K observations
            ents.append((pa, v))
            specs = self._field_specs.get(pa)
            if specs and not self.no_fields:
                meta = read_meta(self, pa)
                if meta:
                    self.meta[pa] = meta
                else:
                    self.meta.pop(pa, None)
            else:
                self.meta.pop(pa, None)
        self.ents = ents
        if self.m is not None:
            self.box_pas = []
            self.boxes, self.projection = project_entities(
                self.m, self.ents, w, h, carry=self.box_pas)
            if self.meta:
                texts = compose_labels(self.meta, self.local_team)
                self.labels = [texts.get(pa) for pa in self.box_pas]
            else:
                self.labels = []      # nothing bound: silently label-free
            self.hits = self.projection["visible"]
        else:
            self.boxes = []
            self.box_pas = []
            self.labels = []
            self.projection = _empty_stats()
            self.projection["candidates"] = len(self.ents)
        return self.boxes

def synthetic_boxes(t, w, h):
    """--fake: five boxes on rails.  No game, no driver, no physical read --
    it isolates 'does the window/menu draw at all' from 'is the feed live'."""
    res = []
    for i in range(5):
        ph = t * 0.7 + i * 1.3
        cx = w * 0.5 + math.sin(ph) * w * 0.28
        cy = h * 0.55 + math.cos(ph * 0.8) * h * 0.18
        bh = 90.0 + 40.0 * (1.0 + math.sin(ph * 0.5)) * 0.5
        bw = bh * BOX_W
        res.append((cx - bw * 0.5, cy - bh, cx + bw * 0.5, cy, 400.0 + i * 300.0))
    return res


# ---------------------------------------------------------------------------
# --from-feed: consume temp\qk_feed.json written by `python qk_va.py --emit`.
# File-fed overlay = consumer-side proof only; the game-read half is NOT
# exercised (R9) and the verdict below says so.  No game, no reads.
# ---------------------------------------------------------------------------
FROM_FEED = os.path.join(os.path.dirname(OUT), "qk_feed.json")
STALE_FEED = 0.5  # s; older than this and the frame counts as stale


def fed_boxes(w, h, max_age=STALE_FEED):
    """Boxes from the producer feed via the same project_entities the live
    pipeline uses (identical 32-float dual-lead matrix).  Sets .note for HUD."""
    import json
    fed_boxes.note = "-"
    try:
        with open(FROM_FEED, "r", encoding="utf-8") as f:
            rec = json.load(f)
    except (OSError, ValueError) as e:
        fed_boxes.note = "unreadable(%s)" % type(e).__name__
        return []
    age = time.time() - float(rec.get("ts", 0))
    m = rec.get("matrix")
    ents = rec.get("ents") or []
    pairs = []
    for i, e in enumerate(ents):
        pos = e.get("pos") if isinstance(e, dict) else None
        if isinstance(pos, list) and len(pos) == 3:
            pairs.append((e.get("ptr", i), (pos[0], pos[1], pos[2])))
    if age > max_age:
        fed_boxes.note = "stale age=%.2fs ents=%d" % (age, len(pairs))
        return []
    if m is None:
        fed_boxes.note = "no-matrix ents=%d age=%.2fs" % (len(pairs), age)
        return []
    if not pairs:
        fed_boxes.note = "no-ents age=%.2fs" % age
        return []
    # The producer stores the authentic <32f> dual-lead pair (leads 0/4) --
    # the same bytes pick_window() scores off the wire.  Normalise to the one
    # 16-float window the projector takes, choosing the higher-scoring lead,
    # exactly like the live path does.  Bad shapes degrade to a note (no raise),
    # so a malformed feed can never kill the overlay.
    if isinstance(m, (list, tuple)) and len(m) == 32:
        cand = []
        for lead in (0, 4):
            sl = list(m[lead:lead + 16])
            if matrix_plausible(sl):
                cand.append((score_vp(sl, pairs, w, h), lead, sl))
        if cand:
            _, _, m = max(cand, key=lambda t: (t[0], -t[1]))
        else:
            fed_boxes.note = "implausible-matrix(32) ents=%d age=%.2fs" % (len(pairs), age)
            return []
    elif isinstance(m, (list, tuple)) and len(m) == 16:
        m = list(m)
        if not matrix_plausible(m):
            fed_boxes.note = "implausible-matrix(16) ents=%d age=%.2fs" % (len(pairs), age)
            return []
    else:
        fed_boxes.note = "bad-matrix-shape ents=%d age=%.2fs" % (len(pairs), age)
        return []
    boxes, proj = project_entities(m, pairs, w, h)
    fed_boxes.note = "age=%.2fs ents=%d visible=%d" % (
        age, len(pairs), proj.get("visible", -1) if isinstance(proj, dict) else -1)
    return boxes


def draw_boxes(ov, boxes, cfg, ox, oy, accent, accent2, labels=None):
    for i, (x0, y0, x1, y1, depth) in enumerate(boxes):
        if cfg["filled"]:
            ov.fill(ox + x0, oy + y0, ox + x1, oy + y1, accent2)
        if cfg["glow"]:
            ov.frame(ox + x0 - 2, oy + y0 - 2, ox + x1 + 2, oy + y1 + 2, accent2,
                     cfg["thick"])
        ov.frame(ox + x0, oy + y0, ox + x1, oy + y1, accent, cfg["thick"])
        if cfg["dist"]:
            ov.text(ox + x0, oy + y0 - 20, "%du" % int(depth), accent, small=True)
        lab = labels[i] if labels is not None and i < len(labels) else None
        if lab:
            ov.text(ox + x0, oy + y0 - (36 if cfg["dist"] else 20), lab,
                    accent, small=True)


def run(cfg, seconds, fake, wide, cap, base, rva):
    import dumplive as dl
    feed = bool(flag("from-feed"))   # consume qk_feed.json instead of reading the game
    fake = fake or feed              # identical desktop-surface handling as --fake
    fps = arg("fps", 60.0, float)    # render cap (go15/M3): 60 = legacy feel; 0 = uncapped
    frame_dt = 1.0 / fps if fps > 0 else 0.0
    t0 = time.time()
    pid = None if fake else dl.find_pid()
    rect = screen_rect() if fake else None
    wait_deadline = t0 + arg("window-wait", 60, float)
    announced_wait = False
    while not valid_client(rect):
        now = time.time()
        if pid is None or now >= wait_deadline or (seconds and now - t0 >= seconds):
            out("RESULT: window=unavailable fake=%s pid=%s" % (fake, pid))
            out("VERDICT: PARTIAL (SKIPPED rendering, R9)")
            return 3
        if not announced_wait:
            out("waiting up to %.0fs for a game-owned client area (no desktop fallback)"
                % max(0.0, wait_deadline - t0))
            announced_wait = True
        time.sleep(0.25)
        pid = dl.find_pid()
        rect = game_rect(pid) if pid else None
    out("window rect: %s  (%dx%d)" % (rect, rect[2] - rect[0], rect[3] - rect[1]))
    ov = None
    sess = None
    try:
        try:
            ov = Overlay(rect)
            ov.set_stream_safe(flag("stream-safe"))
            out("window capture: %s" % ov.capture_policy)
        except OSError as e:
            out("VERDICT: FAIL - %s" % e)
            return 2
    except BaseException:
        if ov is not None:
            ov.close()
        raise
    ox, oy = rect[0], rect[1]
    w, h = ov.w, ov.h
    keep = Keys()
    if not fake:
        try:
            sess = Session(cap=cap, wide=wide, base=base, rva=rva)
        except OSError as e:
            ov.close()
            out("gio: %s" % e)
            out("VERDICT: FAIL - could not open the read-only physical transport")
            return 2
        got = sess.prime()
        out(source_summary(sess.source))
        out("census_discovered=%d candidate_eligible=%d decoded=%d "
            "local_excluded=%d read_failed=%d dropped=%d skipped_unverified=%d "
            "expired=%d round=%s"
            % (sess.seed_total, len(got) + sess.local_excluded + sess.read_failures
               + sess.dropped, len(got), sess.local_excluded, sess.read_failures,
               sess.dropped, sess.skipped_unverified, sess.expired_events,
               "suspected" if sess.round_transition else "no"))
        out("image_pa=%#x vp_rva=%#x pid=%s" % (sess.base or 0, sess.rva, sess.pid))
        if not got:
            out("live gate: candidates; NO VALIDATED PLAYERS. No boxes will be drawn.")
    boxes = []
    accent = SCHEMES[cfg["scheme"] % len(SCHEMES)][1]
    accent2 = 0x00303030
    next_read = 0.0
    next_status = 0.0
    next_log = t0 + 5.0
    frames = 0
    read_ticks = 0
    rendered_box_frames = 0
    reads_at_start = 0
    last_boxes = 0
    reason = "time"
    no_pid_since = None
    last_source_gate = None
    previous_rect = rect
    while True:
        t = time.time()
        if seconds and t - t0 >= seconds:
            break
        ov.pump()
        if not ov.hwnd:
            reason = "window destroyed"
            break
        for vk, name, action, label in KEYS:
            pressed = keep.hit(vk)
            if not pressed:
                continue
            if action != "menu" and not cfg["menu"]:
                continue  # poll state but ignore feature keys while the menu is closed
            moved = apply_key(cfg, action)
            out("key %-6s %-6s -> %s" % (name, label, moved[1]))
            cfg_save(cfg)
            accent = SCHEMES[cfg["scheme"] % len(SCHEMES)][1]
            next_read = 0.0
        save_pressed = keep.hit(VK_F8)
        if save_pressed and cfg["menu"]:
            out("key F8     save   -> %s (%s)" % (CFG, "ok" if cfg_save(cfg) else "FAILED"))
        if keep.hit(VK_END):
            reason = "END"
            break
        if t >= next_read:
            read_ticks += 1
            if feed:
                boxes = fed_boxes(w, h)
            elif fake:
                boxes = synthetic_boxes(t - t0, w, h)
            else:
                new_pid = dl.find_pid()
                current_rect = game_rect(pid) if new_pid == pid else None
                if new_pid != pid:
                    if no_pid_since is None:
                        no_pid_since = t
                    if new_pid is not None or t - no_pid_since >= arg("window-wait", 60, float):
                        out("RESULT: game_pid old=%s new=%s" % (pid, new_pid))
                        reason = "game gone" if new_pid is None else "game pid changed"
                        break
                    sess.allowed_to_draw = False
                    sess.provenance_lost = True
                    boxes = []
                elif not valid_client(current_rect):
                    sess.allowed_to_draw = False
                    sess.provenance_lost = True
                    sess.ents = []
                    boxes = []
                else:
                    no_pid_since = None
                    new_rect = current_rect
                    if new_rect != previous_rect:
                        if not valid_client(new_rect):
                            sess.allowed_to_draw = False
                            boxes = []
                        else:
                            ov.resize(new_rect)
                            previous_rect = new_rect
                            ox, oy = new_rect[0], new_rect[1]
                            w, h = ov.w, ov.h
                            out("window resized: %s" % (new_rect,))
                    if reads_at_start == 0:
                        reads_at_start = sess.ph.reads
                    if sess.provenance_lost:
                        sess.allowed_to_draw = False
                        sess.provenance_lost = False
                        sess.next_refresh = 0.0  # must revalidate via prime after a game return
                    boxes = sess.tick(w, h)
            last_boxes = len(boxes)
            next_read = t + 1.0 / max(1, cfg["hz"])
        ov.clear()
        if cfg["esp"]:
            draw_boxes(ov, boxes, cfg, ox, oy, accent, accent2,
                       labels=getattr(sess, "labels", None))
        feed_label = pipeline_summary(sess)
        if feed and getattr(fed_boxes, "note", "-") != "-":
            feed_label = "file-feed %s" % fed_boxes.note
        if sess is not None and sess.source:
            src = sess.source
            key = (os.path.normcase(src["path"]), src.get("captured_ts"),
                   src.get("pid"), src.get("gate"))
            if key != last_source_gate:
                out("source changed: %s; %s" % (key, source_summary(src)))
                last_source_gate = key
        if cfg["menu"]:
            draw_menu(ov, cfg, feed_label, accent)
        else:
            draw_status(ov, feed_label + " [INSERT] menu", accent)
        painted = ov.present()
        if painted and cfg["esp"] and last_boxes > 0:
            rendered_box_frames += 1
        frames += 1
        if t >= next_status:
            elapsed = max(0.001, t - t0)
            rps = 0.0
            if sess is not None:
                rps = (sess.ph.reads - reads_at_start) / elapsed if reads_at_start else 0.0
            status("t=%.1fs frames=%d fps=%.1f boxes=%d hz=%d reads/s=%.0f hits=%s"
                   % (elapsed, frames, frames / elapsed, last_boxes, cfg["hz"], rps,
                      "-" if sess is None else sess.hits))
            next_status = t + 1.0
        if t >= next_log:
            detail = pipeline_summary(sess) if sess is not None else feed_label
            if sess is not None:
                detail += " reads=%d refused=%d failed=%d" % (
                    sess.ph.reads, sess.ph.refused, sess.ph.failed)
            out("t=%.1fs frames=%d %s" % (t - t0, frames, detail))
            next_log = t + 5.0
        dt = frame_dt - (time.time() - t)
        if dt > 0:
            time.sleep(dt)
    elapsed = time.time() - t0
    cfg_save(cfg)
    if sess is not None:
        sess.ph.close()
    ov.close()
    stats = ""
    if sess is not None:
        stats = (" reads=%d refused=%d failed=%d" %
                 (sess.ph.reads, sess.ph.refused, sess.ph.failed))
    out("stopped by %s after %.1fs: frames=%d fps=%.1f boxes=%d%s"
        % (reason, elapsed, frames, frames / max(0.001, elapsed), last_boxes, stats))
    out("read-cadence: ticks=%d eff_hz=%.1f target_hz=%d"
        % (read_ticks, read_ticks / max(0.001, elapsed), cfg["hz"]))
    if feed:
        game_present = dl.find_pid() is not None
        rc, verdict = ((0, "PARTIAL (R9) - file-fed overlay drew; game-read half "
                          "not exercised (consumer proof only)") if frames else
                       (1, "FAIL - no file-fed frames rendered"))
        if game_present:
            verdict += "; game present during consume"
    elif fake:
        rc, verdict = (0, "PASS - synthetic UI only; NO GAME HALF RAN") if frames else \
                      (1, "FAIL - no synthetic frames rendered")
    else:
        alive = dl.find_pid() == pid if pid else False
        rc, verdict = live_verdict(sess, alive, valid_client(game_rect(pid) if alive else None),
                                  render_observed=rendered_box_frames > 0)
        if reason in ("game gone", "game pid changed"):
            rc, verdict = 3, "PARTIAL (SKIPPED rendering, R9)"
    out("RESULT: %s frames=%d boxes=%d%s" % (reason, frames, last_boxes, stats))
    out("VERDICT: %s" % verdict)
    out("coverage: NOT ESTABLISHED - number of boxes never proves the expected match population")
    return rc


# ---------------------------------------------------------------------------
# --check: the read-back that decides whether the cached offsets still speak
# ---------------------------------------------------------------------------
def check(wide, cap):
    import dumplive as dl
    t0 = time.time()
    out("=== qk_live check %s ===" % now())
    pid = dl.find_pid()
    out("game pid=%s" % pid)
    if pid is None:
        out("VERDICT: PARTIAL - game not running, nothing read (R9)")
        return 3
    try:
        s = Session(cap=cap, wide=wide)
    except OSError as e:
        out("gio: %s" % e)
        out("VERDICT: FAIL - could not open the physical read transport")
        return 2
    ph = s.ph
    try:
        out("ram_top=%#x ranges=%d (%s) reads=%d"
            % (ph.g.ram_top, len(ph.ranges), ph.note, ph.reads))
        out("image_pa=%#x vp_rva=%#x" % (s.base or 0, s.rva))
        if s.base is None:
            out("VERDICT: FAIL - temp\\qk_offsets.txt has no image_pa")
            return 1
        got = s.prime()
        out(source_summary(s.source))
        out("pipeline discovered=%d decoded=%d local_excluded=%d read_failed=%d "
            "dropped=%d skipped_unverified=%d (%d reads)"
            % (s.seed_total, len(got), s.local_excluded, s.read_failures,
               s.dropped, s.skipped_unverified, ph.reads))
        for i, (pa, v) in enumerate(got[:8]):
            out("  seed%d %#x  (%.2f, %.2f, %.2f)" % (i, pa, v[0], v[1], v[2]))
        if not got:
            out("RESULT: no eligible player candidates (reads=%d)" % ph.reads)
            out("VERDICT: PARTIAL - no validated player candidates; rendering not evidenced")
            return 4
        b = ph.read(s.base + s.rva, 0x80)
        if not b:
            out("VERDICT: FAIL - the matrix read was refused by the interval set")
            return 1
        f = struct.unpack("<32f", b)
        for lead in (0, 4):
            out("window @%#x +%d:" % (s.rva, lead))
            for r in range(4):
                out("   %s" % " ".join("%12.6g" % x for x in f[lead + r * 4: lead + r * 4 + 4]))
        rect = game_rect(pid)
        if not valid_client(rect):
            out("VERDICT: PARTIAL (SKIPPED rendering, no game client area; R9)")
            return 3
        s.tick(rect[2] - rect[0], rect[3] - rect[1])
        out("chosen lead=%d hits=%d/%d boxes=%d rva=%#x wide_rva=%s"
            % (s.lead, s.hits, len(s.ents), len(s.boxes), s.rva,
               "%#x" % s.wide_rva if s.wide_rva is not None else "-"))
        for i, bx in enumerate(s.boxes[:10]):
            out("  box%d  x %.0f..%.0f  y %.0f..%.0f  d=%.0f"
                % (i, bx[0], bx[2], bx[1], bx[3], bx[4]))
        # M2/B1: declared-field header dump -- header table + this tick's live
        # values for every record that declared "fields".  Spec-bearing records
        # whose position died this tick show <no-meta>; a field that refused to
        # decode in a living record shows <absent>.  Counts only; no verdicts.
        spec_recs = sum(1 for sp in s._field_specs.values() if sp)
        if spec_recs:
            named = 0
            for pa, _v in s.ents:
                specs = s._field_specs.get(pa)
                if not specs:
                    continue
                named += 1
                meta = s.meta.get(pa)
                out(" fields@%#x:" % pa)
                for nm, fo, fsz, ff in specs:
                    val = meta.get(nm) if meta else None
                    if val is None:
                        txt = "<no-meta>" if meta is None else "<absent>"
                    elif ff == "str-u16le":
                        txt = repr(str(val)[:META_STR_MAX])
                    elif ff == "f32":
                        txt = "%.6g" % val
                    else:
                        txt = "%d" % val
                    out("   %-12s +%#05x %s(%d) = %s" % (nm, fo, ff, fsz, txt))
            out("field-plan: declared_recs=%d alive_named=%d field_reads=%d "
                "failures=%d partial=%d local_reads=%d local_team=%s"
                % (spec_recs, named, s.field_reads, s.field_failures,
                   s.field_partial, s.local_meta_reads,
                   s.local_team if s.local_team is not None else "-"))
        t = time.time() - t0
        alive = dl.find_pid() == pid
        out("elapsed=%.2fs reads=%d refused=%d failed=%d game_alive=%s"
            % (t, ph.reads, ph.refused, ph.failed, alive))
        boxes = len(s.boxes)
        out("projection %s" % s.projection)
        rc, verdict = live_verdict(s, alive, valid_client(rect))
        out("RESULT: checked source=%s candidates=%d boxes=%d reads=%d"
            % (s.source.get("gate"), len(s.ents), boxes, ph.reads))
        out("VERDICT: %s" % verdict)
        out("coverage: NOT ESTABLISHED - count(expected_remote_players)=/=this_single_tick_sample")
        return rc
    finally:
        ph.close()


def _relaunch():
    import dumplive as dl
    args = [a for a in sys.argv[1:] if a != "--no-elevate"]
    params = " ".join(['"%s"' % os.path.abspath(__file__)] + args + ["--no-elevate"])
    out("not elevated -> %s" % params)
    msg = dl.run_elevated(params)
    out(msg)
    return 0


def main():
    global _logf
    mode = "fake" if flag("fake") else ("check" if flag("check") else "run")
    cap = arg("seeds", arg("max", 0, int), int)
    if cap < 0:
        raise ValueError("--seeds must be 0 (unlimited) or a positive parser/display budget")
    wide = flag("wide")
    seconds = arg("seconds", 0, int)
    base = arg("base", None, lambda v: int(v, 0))
    rva = arg("rva", None, lambda v: int(v, 0))
    if mode == "check":
        seconds = 0
    try:
        _logf = open(OUT, "a", encoding="utf-8")
    except OSError:
        _logf = None
    out("")
    out("=== qk_live %s %s mode=%s args=%s ===" % (now(), time.strftime("%d/%m"),
                                                  mode, " ".join(sys.argv[1:]) or "-"))
    try:
        if mode == "fake":
            cfg = cfg_load()
            cfg["hz"] = arg("hz", cfg["hz"], int)   # parity with --run path (M3.1):
            cfg = sanitize_config(cfg)              # synthetic lane drives the real ladder
            return run(cfg, seconds or 20, True, False, cap, base, rva)
        import dumplive as dl
        if not dl.elevation() and not flag("no-elevate"):
            return _relaunch()
        if mode == "check":
            return check(wide, cap)
        cfg = cfg_load()
        cfg["hz"] = arg("hz", cfg["hz"], int)
        cfg = sanitize_config(cfg)
        return run(cfg, seconds, False, wide, cap, base, rva)
    finally:
        if _logf is not None:
            _logf.close()
            _logf = None


if __name__ == "__main__":
    sys.exit(main())
