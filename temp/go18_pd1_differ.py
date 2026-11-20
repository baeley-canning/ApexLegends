"""go18_pd1_differ -- PD-1 mechanical differ: dm33(new build 0x6AEBBC7D) vs dm32(0x6ADBF892).

Keys every (class,name) datamap row and reports, for the monitored set-B fields,
SAME / MOVED(old->new) / ABSENT / NAME-ONLY; plus counts over the whole map and
every changed row inside DT_Player*.  Writes temp/_go18_pd1_differ.txt (R3: file
is the verdict).  Read-only over both TSVs; changes nothing.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = os.path.join(HERE, "dm32_fields.tsv")
NEW = os.path.join(HERE, "dm33_fields.tsv")
OUT = os.path.join(HERE, "_go18_pd1_differ.txt")

# (class, name, old-pinned, alias) -- offsets from FACTS/FIELD_MAP_LOCAL (set-B);
# old-pinned is the LOCAL measured offset the candidate table declares today.
MONITORED = [
    ("DT_Player", "m_iHealth", 0x330, "hp"),
    ("DT_Player", "m_iMaxHealth", 0x470, "max_hp"),
    ("DT_Player", "m_bleedoutState", 0x27A0, "bleed"),
    ("DT_Player", "m_lifeState", 0x698, "life"),
    ("DT_Player", "m_extraShieldHealth", 0x3030, "extra_shield"),
    ("DT_Player", "m_extraShieldTier", 0x3034, "extra_tier"),
    ("DT_BaseEntity", "m_iTeamNum", 0x340, "team"),
    ("DT_BaseCombatCharacter", "m_shieldHealth", 0x18C, "main_shield_a"),
    ("DT_BaseCombatCharacter", "m_shieldHealthMax", 0x190, "main_shield_b"),
]


def load(path):
    rows = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for ln, line in enumerate(fh):
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 7 or parts[0] in ("class", ""):
                continue
            cls, idx, typ, off, size, flags, name = parts[:7]
            try:
                off_i = int(off, 0)
            except ValueError:
                continue
            rows[(cls, name)] = (off_i, idx, size, ln + 1)
    return rows


lines = []


def p(s=""):
    lines.append(s)


p("# go18_pd1_differ %s" % os.path.getmtime(NEW))
try:
    old = load(OLD)
    new = load(NEW)
except OSError as e:
    p("ERROR %r" % e)
else:
    p("rows_old=%d rows_new=%d" % (len(old), len(new)))
    changed = [(k, old[k][0], new[k][0])
               for k in old.keys() & new.keys() if old[k][0] != new[k][0]]
    gone = [k for k in old.keys() - new.keys()]
    born = [k for k in new.keys() - old.keys()]
    p("changed_rows=%d gone=%d born=%d" % (len(changed), len(gone), len(born)))
    p("")
    p("-- monitored set-B rows (class, name): old_pin | old | new | verdict --")
    absurd_count = 0
    for cls, name, pin, alias in MONITORED:
        o = old.get((cls, name))
        n = new.get((cls, name))
        o_off = o[0] if o else None
        n_off = n[0] if n else None
        if o_off is not None and n_off is not None:
            if o_off == n_off:
                verdict = "SAME"
                note = "" if o_off == pin else " (!pin-mismatch old=%#x)" % o_off
            else:
                verdict = "MOVED"
                note = ""
                absurd_count += 1
            p("  %-9s %-28s %-32s pin=%#06x old=%s new=%s"
              % (alias, (cls + "." + name), verdict, pin,
                 ("%#x" % o_off), ("%#x" % n_off)) + note)
        else:
            verdict = "ABSENT" if (o_off is None and n_off is None) else \
                      ("GONE_IN_NEW" if o_off is not None else "NEW_ONLY")
            p("  %-9s %-28s %-32s pin=%#06x old=%s new=%s"
              % (alias, (cls + "." + name), verdict, pin,
                 ("%#x" % o_off if o_off is not None else "-"),
                 ("%#x" % n_off if n_off is not None else "-")))
            if o_off is not None and n_off is None:
                absurd_count += 1
    p("")
    p("-- every changed row inside DT_Player*/DT_BaseEntity* --")
    shown = 0
    for k, a, b in sorted(changed):
        if k[0].startswith(("DT_Player", "DT_BaseEntity")) and shown < 40:
            p("  %-36s %#x -> %#x" % (k[0] + "." + k[1], a, b))
            shown += 1
    if shown == len(changed):
        p("  (all %d shown)" % shown)
    elif shown == 0:
        p("  (none)")
    else:
        p("  ...(%d of %d shown)" % (shown, len(changed)))
    p("")
    p("shield-name hunt in NEW (any class):")
    hits = 0
    for (cls, name), (off, idx, size, ln) in sorted(new.items()):
        if "shield" in name.lower() and hits < 12:
            p("  %-28s.%-32s off=%#x sz=%s L%d" % (cls, name, off, size, ln))
            hits += 1
    p("")
    p("RESULT: changed_rows=%d DT_Changed_under_Player=%d monitored_moves=%d"
      % (len(changed), shown, absurd_count))
    p("VERDICT: %s"
      % ("PATCH-CLEAN - monitored set-B offsets UNCHANGED, set-B identity carries"
         if absurd_count == 0 and not any(
             k[0].startswith("DT_Player") for k, a, b in changed)
         else "PATCH-DIRTY - %d monitored row(s) MOVED/ABSENT; set-B re-tagging owed"
              % absurd_count))

with open(OUT, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("\n".join(lines))
