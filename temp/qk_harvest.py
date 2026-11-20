"""qk_harvest - READ-ONLY profiler for temp/qk_feed.json (set-B adjudication aid).

Loads the emitted feed, then prints:
  record count, key union, sample records
  histograms for any name_how / team / kind-like key
  name_how x team cross-tab (props vs players separation)
  distinct namePtr-ish offsets with counts
Verdict text -> temp/harvest_out.txt. Never writes the feed. Usage:
  python temp\\qk_harvest.py            profile + distributions
"""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FEED = os.path.join(HERE, "qk_feed.json")
OUT = os.path.join(HERE, "harvest_out.txt")

class _Sink:
    """Dual-out logger: keeps an in-memory copy and mirrors to stdout."""

    def __init__(self):
        self.buf = []

    def write(self, s=""):
        self.buf.append(str(s))
        print(s)


NAME_KEYS = ("name_how", "nameHow", "how")
TEAM_KEYS = ("team", "team_id", "tid")
PTR_KEYS = ("name_ptr", "namePtr", "np_off")


def load(path):
    """Try whole-file JSON first, then line-delimited (NDJSON) fallback."""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        txt = f.read()
    try:
        obj = json.loads(txt)
        return obj if isinstance(obj, list) else [obj]
    except json.JSONDecodeError:
        rows = []
        for ln in txt.splitlines():
            ln = ln.strip().rstrip(",")
            if not ln or ln in ("[", "]"):
                continue
            try:
                rows.append(json.loads(ln))
            except json.JSONDecodeError:
                continue
        return rows


def pick(rec, keys):
    for k in keys:
        if k in rec:
            return rec[k]
    return None


def hist(rows, keys, title, snk):
    c = collections.Counter(repr(pick(r, keys)) for r in rows)
    snk.write("")
    snk.write("[%s] (%d distinct)" % (title, len(c)))
    for val, cnt in c.most_common(15):
        snk.write("  %-28s %6d" % (val[:28], cnt))


def cross(rows, snk):
    ct = collections.Counter()
    for r in rows:
        n, tv = pick(r, NAME_KEYS), pick(r, TEAM_KEYS)
        if n is not None and tv is not None:
            ct[(repr(n), repr(tv))] += 1
    snk.write("")
    if not ct:
        snk.write("[cross-tab] unavailable (missing name_how or team key)")
        return
    snk.write("[name_how x team]")
    for (n, tv), cnt in sorted(ct.items()):
        snk.write("  %-24s team=%-14s %6d" % (n[:24], tv[:14], cnt))


def main(snk):
    snk.write("=== qk_harvest ===")
    if not os.path.exists(FEED):
        snk.write("FEED MISSING: %s" % FEED)
        return
    snk.write("feed sz=%d" % os.path.getsize(FEED))
    rows = load(FEED)
    snk.write("records parsed: %d" % len(rows))
    if not rows:
        snk.write("empty feed - nothing to adjudicate")
        return
    if not isinstance(rows[0], dict):
        snk.write("record[0] not a dict: %r" % (rows[0],)[:80])
        return
    keys = sorted({k for r in rows if isinstance(r, dict) for k in r})
    snk.write("key union (%d): %s" % (len(keys), ", ".join(keys)))
    hist(rows, NAME_KEYS, "name_how", snk)
    hist(rows, TEAM_KEYS, "team", snk)
    cross(rows, snk)
    hist(rows, PTR_KEYS, "namePtr-ish", snk)
    snk.write("")
    snk.write("[samples]")
    for r in rows[:3]:
        snk.write("  " + json.dumps(r)[:400])
    snk.write("=== done ===")


if __name__ == "__main__":
    with open(OUT, "w", encoding="utf-8") as f:
        snk = _Sink()
        _real = sys.stdout
        sys.stdout = f
        try:
            main(snk)
        finally:
            sys.stdout = _real

