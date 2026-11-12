r"""h396 -- exact EPROCESS path, no broad guesses.

Use installed SystemDriverInformation to get ntoskrnl base and exported
PsInitialSystemProcess RVA. KUSER_SHARED_DATA is statically mapped by Windows
in every process and therefore also in the kernel map. Read linked process
objects along that chain via MapK, locate pid 14008, read its DTB at +0x28.
If the chain is all kernel VAs, the same gdrv3 reader translates them with
the current CR3 when started from its IOCTL dispatch, so attempted translation
is checked with NT headers locally before relying on it for arbitrary control.
"""
import ctypes as C
import os
import struct
import sys
import subprocess
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread

OUT = os.path.join(ROOT, "temp", "h396_kernel_chain.txt")
def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


def modules():
    n = 1 << 20
    buf = C.create_string_buffer(n)
    need = C.c_ulong(0)
    st = C.windll.ntdll.NtQuerySystemInformation(11, buf, n, C.byref(need))
    if st == 0xC0000004:
        buf = C.create_string_buffer(need.value + 4096)
        st = C.windll.ntdll.NtQuerySystemInformation(11, buf, C.sizeof(buf), C.byref(need))
    if st:
        raise OSError(st, "no module info")
    count = struct.unpack_from("<I", buf.raw, 0)[0]
    for i in range(count):
        off = 8 + 16 + i * 0x128
        image, size, flags, idx, loadcount, loops = struct.unpack_from("<QQIIII", buf.raw, off)
        path = buf.raw[off + 24:].split(b"\0")[0]
        if path.lower().endswith(b"\\ntoskrnl.exe"):
            return image, size, off
    raise OSError("no kernel found")


open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say("=== h396 exact kernel process lookup %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
image, size, moff = modules()
say("kernel_base=%#x size=%#x" % (image, size))
fn = os.path.join(ROOT, "temp", "h396_ntexports.txt")
subprocess.run(["C:\\BuildTools\\VC\\Tools\\MSVC\\14.44.35207\\bin\\Hostx64\\x64\\dumpbin.exe",
                "/exports", r"C:\Windows\System32\ntoskrnl.exe"], stdout=open(fn, "w"), text=True)
ps = None
for ln in open(fn):
    if ln.strip().endswith("PsInitialSystemProcess"):
        ps = int(ln.split()[2], 16)
if not ps:
    raise RuntimeError("PsInitialSystemProcess export not found")
say("PsInitialSystemProcess=%#x kernel_va=%#x" % (ps, image + ps))
g = gio.Gio(chunk=0x1000)
ranges, note = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = qk_va.Ram(ranges).page_ok
mr = qk_gdrv_mapread.install(g)
k = C.WinDLL("kernel32", use_last_error=True)
k.GetProcAddress.argtypes = [C.c_void_p, C.c_char_p]
k.GetProcAddress.restype = C.c_void_p
k.GetModuleHandleW.restype = C.c_void_p
api = k.GetProcAddress(k.GetModuleHandleW("kernel32.dll"), b"MapViewOfFile")
say("gdrv_opened PEB=%#x" % qk_va._peb_va(14008))

def kernel_read(va, n=8):
    """Translate a kernel VA through the driver's own active address space."""
    ok, pa = g.translate(va)
    if not ok:
        raise OSError(int(pa), "gdrv3 translate kernel VA=%#x failed" % va)
    if (pa & 0xFFF) != (va & 0xFFF) or not mr.in_ram(pa & ~0xFFF, 0x1000):
        raise OSError(22, "unsafe kernel PA=%#x VA=%#x" % (pa, va))
    page = mr.read(pa & ~0xFFF, 0x1000)
    off = pa & 0xFFF
    if off + n > 0x1000:
        return page[off:] + mr.read((pa & ~0xFFF) + 0x1000, off + n - 0x1000)
    return page[off:off+n]


# Positive control, MUST agree before walking the process chain.
local_va = k.GetProcAddress(k.GetModuleHandleW("kernel32.dll"), b"CloseHandle")
expected = C.string_at(C.c_void_p(local_va), 16)
observed = kernel_read(local_va, 16)
say("LOCAL_VA_TRANSLATION_MATCH=%s expected=%s read=%s" %
    (observed == expected, expected.hex(), observed.hex()))
if observed != expected:
    say("VERDICT: BLOCKED - no positive kernel-translate control")
    raise SystemExit(3)

initial = struct.unpack("<Q", kernel_read(image + ps, 8))[0]
say("PsInitialSystemProcess points at EPROCESS=%#x" % initial)
cur = initial
seen = set()
pid = 14008
for _ in range(1000):
    if cur in seen:
        break
    seen.add(cur)
    proc = kernel_read(cur + 0x1D0, 8)
    this_pid = struct.unpack("<Q", proc)[0]
    name = kernel_read(cur + 0x338, 15)
    if this_pid == pid:
        say("APEX_EPROCESS=%#x name=%r pid=%d" % (cur, name, this_pid))
        if name != b"r5apex_dx12.ex\0":
            say("VERDICT: BLOCKED - unexpected identity")
            raise SystemExit(4)
        dtb = struct.unpack("<Q", kernel_read(cur + 0x28, 8))[0] & dl.MASK
        say("DTB=%#x" % dtb)
        rd = qk_va.Reader(g, dtb)
        peb = qk_va._peb_va(pid)
        raw = rd.read(peb + 0x10, 8)
        if not raw:
            say("VERDICT: BLOCKED - DTB cannot read PEB")
            raise SystemExit(5)
        base = struct.unpack("<Q", raw)[0]
        page = rd.read(base, 0x1000)
        meta = dl.validate_pe(page) if page else None
        say("BASE=%#x PE=%s image_pa=%s" % (base, meta, rd.page_pa(base)))
        if meta and meta["size"] == 0xDFB8000:
            qk_va.save_cache(pid, dtb, base)
            say("RESULT: dtb=%#x base=%#x image_pa=%#x MapK=True" %
                (dtb, base, rd.page_pa(base)))
            say("VERDICT: PASS - existing gdrv3 reads Apex VA directly")
            g.close()
            sys.exit(0)
        break
    flink = struct.unpack("<Q", kernel_read(cur + 0x1D8, 8))[0]
    cur = flink - 0x1D8
say("RESULT: Apex not found in %d linked objects" % len(seen))
say("VERDICT: BLOCKED - process link traversal incomplete")
g.close()