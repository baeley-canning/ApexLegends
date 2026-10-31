"""dm32_stats.py -- sanity analysis of dm32_fields.tsv.

Checks that hold for a healthy reconstruction of Source-style datamaps:
  * every field carries a name pointer that resolves to a string
  * offsets inside one class are non-decreasing (datamaps are emitted in
    declaration order, which the compiler keeps in layout order)
  * FIELD_EMBEDDED entries (type 10) carry a typedesc and no size
  * a field size, when present, divides the distance to the next offset
"""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TSV = os.path.join(HERE, "dm32_fields.tsv")

COLS = ("class idx type off size flags name alt typedesc fieldfn "
        "nfields").split()


def load():
    rows = []
    with open(TSV) as fh:
        head = fh.readline()
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) != len(COLS):
                continue
            rows.append(dict(zip(COLS, p)))
    return rows


def num(v):
    return int(v, 16) if v.startswith("0x") else int(v)


def main():
    rows = [r for r in load() if num(r["idx"]) >= 0]
    empty = [r for r in load() if num(r["idx"]) < 0]
    print("fields=%d (+%d sentinels)" % (len(rows), len(empty)))

    nul = [r for r in rows if r["name"] in ("-", "(null)")]
    print("name missing      : %d" % len(nul))
    empty = [r for r in rows if num(r["type"]) == 0 and num(r["off"]) == 0
             and r["name"] in ("-", "(null)")]
    print("empty records     : %d (of %d fields)" % (len(empty), len(rows)))
    ec = collections.Counter(r["class"] for r in empty)
    print("worst classes     : %s"
          % ", ".join("%s:%d/%s" % (c, k, next(r["nfields"] for r in empty
                                                if r["class"] == c))
                      for c, k in ec.most_common(6)))
    byt = collections.Counter(num(r["type"]) for r in rows)
    print("fieldType histogram: %s"
          % ", ".join("%d:%d" % kv for kv in sorted(byt.items())))

    bad_emb = [r for r in rows if num(r["type"]) == 10
               and (r["typedesc"] in ("-", "0x0") or num(r["size"]) != 0)]
    print("embedded w/o desc/with size: %d" % len(bad_emb))

    zsz = [r for r in rows if num(r["type"]) not in (10,) and num(r["size"]) == 0]
    print("non-embedded size 0: %d" % len(zsz))
    for r in zsz[:8]:
        print("   %-28s %-24s type=%-4s off=%s"
              % (r["class"], r["name"], r["type"], r["off"]))

    # offsets should march forward within a class
    back = []
    per = collections.OrderedDict()
    for r in rows:
        per.setdefault(r["class"], []).append(r)
    for cls, fr in per.items():
        last = -1
        for r in fr:
            o = num(r["off"])
            if o < last and num(r["type"]) != 10:
                back.append((cls, r["name"], o, last))
                break
            last = max(last, o)
    print("classes with a backward offset: %d" % len(back))
    for b in back[:8]:
        print("   %-28s %-24s off=%#x after %#x" % b)

    # dup names inside a class are a red flag (mis-gridded records)
    dup = [(c, sorted(n for n, k in collections.Counter(
        r["name"] for r in fr).items() if k > 1))
        for c, fr in per.items()]
    dup = [d for d in dup if d[1]]
    print("classes with duplicate field names: %d" % len(dup))
    for d in dup[:8]:
        print("   %-28s %s" % (d[0], ", ".join(d[1][:6])))

    # per-class coverage: which records never received a name, and are those
    # gaps interior (a writer we failed to replay) or a trailing unwritten run
    # (a sparse array, which is normal)?
    cov = []
    for cls, fr in per.items():
        n = int(fr[0]["nfields"])
        holes = [num(r["idx"]) for r in fr if r["name"] in ("-", "(null)")]
        if not holes:
            continue
        interior = [i for i in holes if i + 1 < n]
        cov.append((cls, len(holes), n, len(interior), interior[:6]))
    cov.sort(key=lambda t: -t[3])
    print("classes w/ unwritten records: %d (%d with interior holes)"
          % (len(cov), sum(1 for t in cov if t[3])))
    for c, nh, n, ni, ex in cov[:10]:
        print("   %-30s empty=%-4d n=%-4d interior=%-3d first=%s"
              % (c, nh, n, ni, ", ".join(str(i) for i in ex)))

    # a fieldType above FIELD_EMBEDDED (10) means the record grid is off or
    # the slot holds something other than a typedescription
    def tv(r):
        return None if r["type"] == "-" else num(r["type"])

    garb = collections.Counter(r["class"] for r in rows
                               if tv(r) is not None
                               and 0x40 < tv(r) != 0xFFFFFFFF)
    print("records w/ impossible fieldType: %d in %d classes"
          % (sum(garb.values()), len(garb)))
    for c, k in garb.most_common(8):
        print("   %-30s %d" % (c, k))

    if len(sys.argv) > 1:
        want = sys.argv[1]
        for c, fr in per.items():
            if c != want:
                continue
            for r in fr:
                print("   %-3s t=%-4s off=%-8s sz=%-4s %-32s %s"
                      % (r["idx"], r["type"], r["off"], r["size"],
                         r["name"], r["typedesc"]))


main()
