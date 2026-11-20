"""go18_stamp_check -- PD-1 trigger prestate + elevation state, file-backed (R3).

Writes temp/_go18_stamp_check.txt. Read that file; the console print is a courtesy.
"""
import os
import struct
import time
import ctypes

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "temp", "_go18_stamp_check.txt")
EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
KNOWN_STAMP = 0x6ADBF892          # the 2026-10-24 build; PD-1 fires if this changes

lines = []


def p(s):
    lines.append(s)


p("# go18_stamp_check %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
try:
    admin = bool(ctypes.windll.shell32.IsUserAnAdmin())
except Exception:
    admin = False
p("shell_elevated=%s" % admin)
try:
    with open(EXE, "rb") as fh:
        hdr = fh.read(4096)
    e_lfanew = struct.unpack_from("<I", hdr, 0x3C)[0]
    if hdr[e_lfanew:e_lfanew + 4] != b"PE\x00\x00":
        raise RuntimeError("bad PE signature")
    ts = struct.unpack_from("<I", hdr, e_lfanew + 8)[0]
    p("ondisk_ts=0x%08X" % ts)
    p("known_build=0x%08X" % KNOWN_STAMP)
    p("PD1_TRIGGER=%s" % (ts != KNOWN_STAMP))
    p("exe_mtime=%s" % time.strftime("%Y-%m-%d %H:%M:%S",
                                     time.localtime(os.path.getmtime(EXE))))
except Exception as e:
    p("ERROR %r" % e)

body = "\n".join(lines) + "\n"
with open(OUT, "w", encoding="utf-8") as fh:
    fh.write(body)
print(body, end="")
