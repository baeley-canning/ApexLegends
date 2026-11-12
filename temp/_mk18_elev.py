r"""_mk18_elev.py -- does dl.run_elevated() actually produce an elevated child here?

The 12:48 qk_image --data --watch launch left a 0-byte log and no child process, so
"runas" is the variable under test, not the driver.  The elevated child re-runs
_mk18_dev.py, which writes admin=... into temp\_mk18_dev.txt; the parent records the
ShellExecuteExW return string.  Read-only.  Writes temp\_mk18_elev.txt.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import dumplive as dl   # noqa: E402

OUT = os.path.join(HERE, "_mk18_elev.txt")
DEV = os.path.join(HERE, "_mk18_dev.py")


def main():
    r = dl.run_elevated('"%s"' % DEV)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("run_elevated -> %r\n" % (r,))
        f.write("child script = %s\n" % DEV)
        try:
            with open(os.path.join(HERE, "_mk18_dev.txt"), encoding="utf-8") as g:
                f.write("--- child _mk18_dev.txt ---\n" + g.read())
        except OSError as e:
            f.write("child log missing: %s\n" % e)
    print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
