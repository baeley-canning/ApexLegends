r"""qk_session.py -- one elevated run that does the whole discovery pass on the game.

Why: each elevated python is one UAC prompt.  This does map -> DTB/RVA identity ->
entity-array hunt in a single process, so a live session costs one prompt and one
log file (which is the state feed - R3).

Usage: qk_session.py [--pid=N] [--out=FILE] [--sub=0xADDR]
Exit: 0 if the array hunt produced candidates, 4 if the map failed.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio          # noqa: E402
import qk_va as Q   # noqa: E402


def main():
    out_path = Q.arg("out", os.path.join(Q.TMP, "qk_session_%s.txt"
                                         % time.strftime("%Y%m%d_%H%M%S")))
    Q.set_out(out_path)

    if not Q.dl.elevation() and not Q.flag("no-elevate"):
        argv = [os.path.abspath(sys.argv[0])] + [a for a in sys.argv[1:] if a != "--no-elevate"]
        if not any(a.startswith("--out") for a in argv):
            argv.append("--out=" + Q.OUT_PATH)
        cmd = " ".join('"%s"' % a if " " in a else a for a in argv)
        Q.out("not elevated - relaunching elevated")
        Q.out(Q.dl.run_elevated(cmd))
        return 0

    Q.out("===== qk_session (map -> identity -> entity array) =====")
    pid = Q.arg("pid", 0, lambda s: int(s, 0)) or (Q.dl.find_pid() or 0)
    if not pid:
        Q.out("no game process")
        Q.out("VERDICT: PARTIAL - target absent")
        return 3
    Q.out("target pid=%d" % pid)

    try:
        g = gio.Gio()
    except OSError as e:
        Q.out("gio open failed: %s" % e)
        Q.out("VERDICT: PARTIAL - no transport")
        return 2

    try:
        m = Q.get_map(g, pid)
        if not m:
            Q.out("RESULT: no-dtb")
            Q.out("VERDICT: FAIL - page tables not resolved")
            return 4
        rd = Q.Reader(g, m["dtb"])
        Q.out("map: dtb=%#x base=%#x" % (m["dtb"], m["base"]))
        Q.act_pe(rd, m["base"])
        Q.out("")
        Q.act_find_array(rd, m["base"])
        Q.out("")
        Q.out("reads=%d faults=%d" % (rd.reads, rd.faults))
        return 0
    finally:
        try:
            g.close()
        except Exception:                        # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())
