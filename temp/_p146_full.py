r"""_p146_full.py -- lossless index of dm32.txt (p145 was the lossy helper).

Why: temp\_fields_dm32.txt is 2061 lines against 3226 real rows - it silently
dropped ~1165 rows (named + unnamed) and never carried sz=.  W1/W2 cannot be
authored from it.  This reads the SOURCE (temp\dm32.txt) and emits one line per
row, keeping the class label and the source line number so every later claim is
citable.

Out: temp\_p146_full.txt (R5: own file, never overwrite _fields_dm32.txt).
Row:  <name|UNNAMED>  off sz t fl  D  <class>  L####
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "dm32.txt")
OUT = os.path.join(HERE, "_p146_full.txt")

RE_HEAD = re.compile(r"^###\s+(DT_[A-Za-z0-9_]+)")
RE_ROW = re.compile(r"^\s*field\s+(\d+)\s+0x([0-9a-fA-F]+)\s+"
                    r"t=0x([0-9a-fA-F]+)\s+off=0x([0-9a-fA-F]+)\s+"
                    r"sz=0x([0-9a-fA-F]+)\s+fl=0x([0-9a-fA-F]+)")
RE_ANY_ROW = re.compile(r"^\s*field\s+\d")
RE_NAME = re.compile(r"'([^']*)'")
RE_DESC = re.compile(r"desc=0x([0-9a-fA-F]+)")


def main():
    if not os.path.exists(SRC):
        sys.stderr.write("missing %s\n" % SRC)
        return 2
    classes = []
    rows = []
    order = 0
    malformed = []
    occ = {}
    cur = None
    with open(SRC, "r", encoding="utf-8", errors="replace") as fh:
        for ln, line in enumerate(fh, 1):
            line = line.rstrip("\r\n")
            mh = RE_HEAD.match(line)
            if mh:
                base = mh.group(1)
                occ[base] = occ.get(base, 0) + 1
                cur = base if occ[base] == 1 else "%s#%d" % (base, occ[base])
                if cur not in classes:
                    classes.append(cur)
                continue
            if not RE_ANY_ROW.match(line):
                continue
            if cur is None:
                cur = "DT_(unlabelled)"
                classes.append(cur)
            mr = RE_ROW.match(line)
            if not mr:
                malformed.append(ln)
                continue
            fnum, addr, t, off, sz, fl = mr.groups()
            mn = RE_NAME.search(line)
            name = mn.group(1) if mn else ""
            if not name:
                name = "UNNAMED"
            else:
                # apostrophe-in-name check: exactly the 2 delimiters expected
                if line.count("'") != 2:
                    malformed.append(ln)
            md = RE_DESC.search(line)
            rows.append((cur, int(fnum), int(off, 16), int(sz, 16), int(t, 16),
                         int(fl, 16), bool(md), name, ln, int(addr, 16)))
            order += 1

    named = [r for r in rows if r[7] != "UNNAMED"]
    unnamed = [r for r in rows if r[7] == "UNNAMED"]
    uniq_names = set(r[7] for r in named)
    uniq_pairs = set((r[0], r[7]) for r in named)
    zero_off_named = [r for r in named if r[2] == 0]
    seen = {}
    dup_pairs = {}
    for r in named:
        k = (r[0], r[7])
        seen[k] = seen.get(k, 0) + 1
        if seen[k] > 1:
            dup_pairs.setdefault(k, []).append(r[9])
    # per class counts
    cnt = {}
    for r in rows:
        cnt[r[0]] = cnt.get(r[0], 0) + 1

    with open(OUT, "w", encoding="utf-8") as out:
        out.write("# _p146_full.txt -- generated index of dm32.txt (source of truth)\n")
        out.write("# src=temp/dm32.txt  rows=%d  classes=%d\n" % (len(rows), len(classes)))
        out.write("# named=%d unnamed=%d uniq_names=%d uniq_class_name=%d\n"
                  % (len(named), len(unnamed), len(uniq_names), len(uniq_pairs)))
        out.write("# named_with_off0=%d malformed=%d\n\n"
                  % (len(zero_off_named), len(malformed)))
        bycls = {}
        for r in rows:
            bycls.setdefault(r[0], []).append(r)
        for cls in classes:
            out.write("\n#--- %s  rows=%d\n" % (cls, len(bycls.get(cls, []))))
            for r in bycls.get(cls, []):
                _c, fnum, off, sz, t, fl, hasdesc, name, ln, addr = r
                out.write("%-42s off=0x%05x sz=0x%03x t=0x%04x fl=0x%04x %s %s L%d f%d\n"
                          % (name, off, sz, t, fl, "D" if hasdesc else "-", cls, ln, fnum))
        if dup_pairs:
            out.write("\n# duplicate (class,name) pairs: %d\n" % len(dup_pairs))
            for (cls, name), lns in sorted(dup_pairs.items()):
                out.write("#  %s %s at L%s\n" % (cls, name, ",".join(str(x) for x in lns)))

    print("out=%s" % OUT)
    print("classes=%d rows=%d named=%d unnamed=%d" % (len(classes), len(rows),
                                                     len(named), len(unnamed)))
    print("uniq_names=%d uniq_class_name=%d named_off0=%d dup_pairs=%d malformed=%d"
          % (len(uniq_names), len(uniq_pairs), len(zero_off_named), len(dup_pairs),
             len(malformed)))
    if malformed:
        print("MALFORMED lines: %s" % ",".join(str(x) for x in malformed[:20]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
