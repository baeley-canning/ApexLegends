r"""p83_pid.py -- pick a stable Code.exe to baseline on, and prove it is alive.

pid 19912 died at 06:59:55 while p72-p82 were reading its page tables.  Every
frame those probes called "unreadable" was freed memory: the EPROCESS page
also refused, 0x57e88c000 had been recycled into code, and 0x6c6af0000 was
zeroed between p78 and p81.  So baseline the new instance instead of the new
process's ghost.

Stability rule: the earliest-starting Code.exe is the browser (root) process --
children spawn after it -- so it outlives the renderers.  A window title is
recorded but not required.  Prints the pid and writes it to _p83_pid.txt so
the next probe cannot pick a different process by accident.
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "_p83_pid.txt")

PS = ("Get-Process Code -ErrorAction SilentlyContinue | "
      "ForEach-Object { '{0} {1} {2} {3}' -f $_.Id, $_.StartTime.ToFileTime(), "
      "$_.WorkingSet64, ($_.MainWindowTitle -replace ' ','_') }")


def main():
    lines = []
    r = subprocess.run(["powershell", "-NoProfile", "-Command", PS],
                       capture_output=True, text=True)
    row = []
    for ln in r.stdout.splitlines():
        f = ln.split()
        if len(f) >= 3 and f[0].isdigit():
            row.append((int(f[1]), int(f[0]), int(f[2]),
                        f[3] if len(f) > 3 else ""))
    row.sort()
    lines.append("candidates=%d" % len(row))
    for ft, pid, ws, title in row[:6]:
        lines.append("  pid=%d ws=%dMiB title=%r"
                     % (pid, ws // 1048576, title[:40]))
    if not row:
        lines.append("VERDICT: no Code.exe running")
        pid = 0
    else:
        pid = row[0][1]
        ok = os.path.exists("C:\\Windows\\System32\\ntoskrnl.exe")
        lines.append("chosen pid=%d start=%s"
                     % (pid, time.strftime("%H:%M:%S",
                                           time.localtime(row[0][0] / 1e7 - 11644473600))))
        lines.append("alive=%s" % bool(ok and
                     subprocess.run(["powershell", "-NoProfile", "-Command",
                                     "(Get-Process -Id %d).Id" % pid],
                                    capture_output=True).returncode == 0))
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("%d\n" % pid)
        lines.append("VERDICT: use pid=%d (earliest Code.exe, root process)" % pid)
    with open(os.path.join(HERE, "_p83_pid.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
