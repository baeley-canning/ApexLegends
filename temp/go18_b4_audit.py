"""go18_b4_audit -- B4 rider halves that do not need the meta lane.

(a) handle inventory: GIOV-named handles held by THIS process.  Opens one real
    gio.Gio() first so the enumerator has a guaranteed positive control.
(b) footprint: temp/ files created this sitting (mtime >= today 14:00), flagged
    against the temp/README do-not-edit lane surface.

Same-process NtQueryObject on NtQuerySystemInformation(extended=64) handles --
no duplication, no cross-process blocking risk.  Writes temp/_go18_b4_audit.txt.
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
OUT = os.path.join(HERE, "_go18_b4_audit.txt")
README_PROTECTED = {"qk_feed.json", "qk_live_out.txt", "qk_live_cfg.txt",
                    "qk_live_status.txt", "qk_live_help.txt",
                    "dm32.txt", "dm32_fields.tsv"}

nt = ctypes.WinDLL("ntdll")


def self_giov_handles(timeout=0.5):
    class HDR(ctypes.Structure):
        _fields_ = [("Count", ctypes.c_size_t), ("Reserved", ctypes.c_size_t)]

    class ENT(ctypes.Structure):
        _fields_ = [("Object", ctypes.c_void_p), ("Pid", ctypes.c_size_t),
                    ("Handle", ctypes.c_void_p), ("Access", ctypes.c_uint32),
                    ("Res1", ctypes.c_uint32 * 3)]

    size = 0x200000
    buf = ctypes.create_string_buffer(size)
    for _ in range(6):
        rc = nt.NtQuerySystemInformation(64, buf, size, None)
        if rc == 0:
            break
        size = min(size * 4, 0x4000000)
        buf = ctypes.create_string_buffer(size)
    else:
        return ["<NoEnum>"]
    hdr = ctypes.cast(buf, ctypes.POINTER(HDR)).contents
    arr = ctypes.cast(ctypes.addressof(hdr) + ctypes.sizeof(HDR),
                      ctypes.POINTER(ENT))
    me, out, t0 = ctypes.WinDLL("kernel32").GetCurrentProcessId(), [], time.time()
    for i in range(min(hdr.Count, 300000)):
        e = arr[i]
        if e.Pid != me or time.time() - t0 > timeout:
            if time.time() - t0 > timeout:
                out.append("<NoBudget>")
            break
        class ONI(ctypes.Structure):
            _fields_ = [("Len", wt.USHORT), ("Max", wt.USHORT),
                        ("Pad", wt.USHORT * 2)]
        tmp = ctypes.create_string_buffer(1024)
        if nt.NtQueryObject(wt.HANDLE(e.Handle), 1, tmp, 1024, None) != 0:
            continue
        info = ctypes.cast(tmp, ctypes.POINTER(ONI)).contents
        if 0 < info.Len <= 1000:
            out.append(ctypes.wstring_at(ctypes.addressof(tmp.contents) + 8,
                                         info.Len // 2))
    return out


lines = []


def p(s=""):
    lines.append(s)


p("# go18_b4_audit %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
try:
    import gio
    g = gio.Gio()
    ctrl = "gio_self_open=OK"
    g.close()
except Exception as e:
    ctrl = "gio_self_open=FAILED %r" % e
p(ctrl)
names = self_giov_handles()
dev = [s for s in names if "GIOV" in s.upper()]
p("handles_seen=%d giovani_named=%d" % (len(names), len(dev)))
for s in dev[:8]:
    p("  %s" % s)
p("")
p("-- sitting footprint (temp/, mtime >= today 14:00) --")
cut = time.mktime(time.strptime(
    time.strftime("%Y-%m-%d") + " 14:00:00", "%Y-%m-%d %H:%M:%S"))
rows = []
for fn in sorted(os.listdir(HERE)):
    fp = os.path.join(HERE, fn)
    if os.path.isfile(fp):
        mt = os.path.getmtime(fp)
        if mt >= cut:
            rows.append((time.strftime("%H:%M:%S", time.localtime(mt)), fn,
                         "PROTECTED" if fn in README_PROTECTED else ""))
for tm, fn, tag in rows:
    p("  %s  %-46s %s" % (tm, fn, tag))
p("")
prot = sorted(fn for _, fn, tag in rows if tag)
p("RESULT: handles_seen=%d giovani_named=%d footprint_files=%d protected_touched=%s"
  % (len(names), len(dev), len(rows), prot or "none"))

with open(OUT, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("\n".join(lines))
