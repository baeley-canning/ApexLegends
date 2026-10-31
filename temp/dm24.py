"""Final schema extractor -- uses the cached rebuilt .data image (dm11_cache.pkl).

Record layout recovered from the DT_HealthKit initializer (0x1418d8d60) and
confirmed by the aggregated store template in dm22.txt (stride 0x68):

    +0x00 i32  fieldType         (0 = void, 10 = embedded, ...)
    +0x04 i32  fieldOffset       (byte offset inside the entity/struct)
    +0x08 i32  0                  (unused / padding)
    +0x0c i32  fieldSize         (1,2,4,8,12,16 seen)
    +0x10 16B  zeros              (flatOffset[?] / tolerance area)
    +0x14 u8   flags              (0x40, 0x08, 0x10, 0x30 seen)
    +0x18 i32  extra              (0x08..0x100 seen)
    +0x20 ptr  pSaveRestoreOps / type helper (or 0)
    +0x28 ptr  fieldName         ("m_xxx", sentinel 'should_never_see_this')
    +0x50 ptr  input/proxy func  (or 0)
    +0x58 i32  -1                 (record sentinel)
    +0x5c i32  1                  (record sentinel)

Proof the base sits 0x28 before the name slot and not 0x38: the initializer
does `lea rcx, [.data+0xb3811a8]` and stores it as a nested datamap's
dataDesc while the array starts at 0xb381140 (first movups zero-fill), i.e.
0xb3811a8 is exactly base + 1*0x68.

Outputs temp/dm24_layout.txt (template + anchors + per-class counts)
        temp/dm24_fields.tsv  (class, field, type, offset, size, flags)
"""
import os
import pickle
import struct
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
out = []


def p(s=""):
    out.append(s)


with open(os.path.join(HERE, "dm11_cache.pkl"), "rb") as fh:
    C = pickle.load(fh)
img, slots, funcs, ident = C["img"], C["slots"], C["funcs"], C["ident"]
dt_leas = C["dt_leas"]

STRIDE = 0x68
T_OFF, F_OFF, S_OFF = 0x00, 0x04, 0x0C
NAME_OFF = 0x28
FLAGS_OFF, EXTRA_OFF = 0x14, 0x18


def get(va, n):
    b = bytearray()
    for k in range(n):
        v = img.get(va + k)
        if v is None:
            return None
        b.append(v)
    return bytes(b)


def u32(va):
    b = get(va, 4)
    return None if b is None else struct.unpack("<I", b)[0]


def u64(va):
    b = get(va, 8)
    return None if b is None else struct.unpack("<Q", b)[0]


def i32(va):
    b = get(va, 4)
    return None if b is None else struct.unpack("<i", b)[0]


def u8(va):
    b = get(va, 1)
    return None if b is None else b[0]


def func_of(va):
    lo, hi = 0, len(funcs) - 1
    while lo <= hi:
        m = (lo + hi) // 2
        if funcs[m][1] <= va:
            lo = m + 1
        elif funcs[m][0] > va:
            hi = m - 1
        else:
            return funcs[m]
    return None


# class attribution: the DT_* string lea'd by the initializer that owns the slot
dt_by_func = defaultdict(list)
for iva, dtva in dt_leas:
    f = func_of(iva)
    if f:
        dt_by_func[f[0]].append((iva, ident.get(dtva, "?")))


def class_for(iva):
    f = func_of(iva)
    if not f:
        return None
    cand = dt_by_func.get(f[0], [])
    if not cand:
        return None
    before = [c for c in cand if c[0] <= iva]
    return (before[-1] if before else cand[0])[1]


# ---------------------------------------------------------------------------
# records: one per store of a string pointer into record+0x28
# ---------------------------------------------------------------------------
recs = []
for iva, dst, nm, nva in slots:
    b = dst - NAME_OFF
    r = dict(ins=iva, base=b, name=nm, name_va=nva,
             t=i32(b + T_OFF), off=i32(b + F_OFF), size=i32(b + S_OFF),
             flags=u8(b + FLAGS_OFF) or 0, extra=i32(b + EXTRA_OFF) or 0,
             ops=u32(b + 0x20), cls=class_for(iva))
    if r["t"] is None or r["off"] is None or r["size"] is None:
        continue
    recs.append(r)

ok = [r for r in recs
      if 0 <= r["off"] < 0x10000 and r["off"] % 4 == 0
      and r["size"] in (0, 1, 2, 4, 8, 12, 16, 24, 32, 64)
      and 0 <= r["t"] <= 24]

# ---------------------------------------------------------------------------
# second pass: scan the rebuilt image for name-shaped pointers at base+0x28 so
# records the store tracker missed are recovered too
# ---------------------------------------------------------------------------
import re as _re
NAMERE = _re.compile(r"^(m_|DT_)?[A-Za-z_][A-Za-z0-9_]{1,62}$")
have = {r["base"] for r in recs}
scan_n = 0
for va in img:
    b = va - NAME_OFF
    if b % 4 or b in have:
        continue
    v = u64(va)
    if not v:
        continue
    nm = ident.get(v)
    if not nm or not NAMERE.match(nm):
        continue
    t, off, sz = i32(b + T_OFF), i32(b + F_OFF), i32(b + S_OFF)
    if t is None or off is None or sz is None:
        continue
    if not (0 <= t <= 24 and 0 <= off < 0x10000 and off % 4 == 0
            and sz in (0, 1, 2, 4, 8, 12, 16, 24, 32, 64)):
        continue
    have.add(b)
    scan_n += 1
    recs.append(dict(ins=0, base=b, name=nm, name_va=v, t=t, off=off, size=sz,
                     flags=u8(b + FLAGS_OFF) or 0, extra=i32(b + EXTRA_OFF) or 0,
                     ops=u32(b + 0x20), cls=None, src="scan"))
ok = [r for r in recs
      if 0 <= r["off"] < 0x10000 and r["off"] % 4 == 0
      and r["size"] in (0, 1, 2, 4, 8, 12, 16, 24, 32, 64)
      and 0 <= r["t"] <= 24
      and not (r["t"] == 0 and r["off"] == 0 and r["size"] == 0)]
p("## name slots: %d (+%d from image scan) ; template-consistent records: %d"
  " ; classes: %d"
  % (len(slots), scan_n, len(ok), len({r["cls"] for r in ok if r["cls"]})))

p("")
p("## fieldType histogram (+0x00)")
for v, n in Counter(r["t"] for r in ok).most_common(14):
    p("     %-4d %6d" % (v, n))
p("## fieldSize histogram (+0x0c)")
for v, n in Counter(r["size"] for r in ok).most_common(14):
    p("     %-4d %6d" % (v, n))
p("## type -> size cross-tab (identifies the fieldtype_t enum)")
ts = defaultdict(Counter)
for r in ok:
    ts[r["t"]][r["size"]] += 1
for t in sorted(ts):
    tot = sum(ts[t].values())
    p("     type %-3d n=%-5d sizes %s" % (t, tot, dict(ts[t].most_common(6))))
p("## flags byte histogram (+0x14)")
for v, n in Counter(r["flags"] for r in ok).most_common(10):
    p("     %#04x %6d" % (v, n))
p("## offset%%4: %s" % dict(Counter(r["off"] % 4 for r in ok)))
p("## max field offset: %#x" % max((r["off"] for r in ok), default=0))

# ---------------------------------------------------------------------------
# chains (0x68 stride)
# ---------------------------------------------------------------------------
by = {}
for r in ok:
    by.setdefault(r["base"], r)
bases = sorted(by)
runs, cur = [], []
for b in bases:
    if cur and b - cur[-1] != STRIDE:
        runs.append(cur)
        cur = []
    cur.append(b)
if cur:
    runs.append(cur)

chains = []
for run in runs:
    if len(run) < 2:
        continue
    rs = [by[b] for b in run]
    votes = Counter(r["cls"] for r in rs if r["cls"])
    cls = votes.most_common(1)[0][0] if votes else None
    if cls:                              # one initializer per array -> propagate
        for r in rs:
            if not r["cls"]:
                r["cls"] = cls
    chains.append((run[0], cls, rs))
p("")
p("## chains: %d ; with class: %d ; records: %d"
  % (len(chains), sum(1 for c in chains if c[1]),
     sum(len(c[2]) for c in chains)))

# ---------------------------------------------------------------------------
# anchors
# ---------------------------------------------------------------------------
ANCH = ["m_iHealth", "m_iMaxHealth", "m_iTeamNum", "m_vecOrigin", "m_lifeState",
        "m_localOrigin", "m_localAngles", "m_minimapData", "moveparent",
        "m_iName", "m_hOwnerEntity", "m_currentFramePlayer"]
p("")
p("### anchors (class, type, offset, size, flags)")
for a in ANCH:
    hits = [r for r in ok if r["name"] == a]
    p("")
    p("%s  (%d)" % (a, len(hits)))
    for r in sorted(hits, key=lambda r: (str(r["cls"]), r["base"]))[:14]:
        p("    %-38s type=%-3s off=%#-7x size=%-3s flags=%#04x%s"
          % (r["cls"], r["t"], r["off"], r["size"], r["flags"],
             "" if r["cls"] else "  (<-no class)"))

# ---------------------------------------------------------------------------
# per-class dump
# ---------------------------------------------------------------------------
per = defaultdict(dict)
for r in ok:
    if r["cls"]:
        per[r["cls"]].setdefault(r["name"], r)
p("")
p("### per-class summary")
p("## classes: %d ; fields: %d" % (len(per), sum(len(v) for v in per.values())))
for cls, f in sorted(per.items(), key=lambda kv: -len(kv[1]))[:40]:
    mx = max((r["off"] for r in f.values()), default=0)
    p("    %-42s fields=%-4d max_off=%#x" % (cls, len(f), mx))

rows = ["class\tfield\ttype\toffset\tsize\tflags\tbase"]
for cls, f in sorted(per.items()):
    for nm, r in sorted(f.items(), key=lambda kv: kv[1]["off"]):
        rows.append("%s\t%s\t%d\t%#x\t%d\t%#x\t%#x"
                    % (cls, nm, r["t"], r["off"], r["size"], r["flags"],
                       r["base"]))
with open(os.path.join(HERE, "dm24_fields.tsv"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(rows) + "\n")
p("")
p("## wrote dm24_fields.tsv: %d rows" % (len(rows) - 1))

with open(os.path.join(HERE, "dm24_layout.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("\n".join(out))
