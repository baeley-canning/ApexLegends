"""readprobe.py -- which (access mask, read primitive) pair actually reads Apex?

namehunt showed:
  * syscall 0x3F (NtReadVirtualMemory) with a raw stub -> 0xC000000D, same as
    ntdll, so the block is NOT a user-mode ntdll hook;
  * NtReadVirtualMemoryEx -> 0xC0000022 (ACCESS_DENIED), i.e. the *real* access
    check says the handle has no PROCESS_VM_READ.

0xD from one path and 0x22 from the other means the handle that
OpenProcess(0x1FFFFF) returned was stripped (EAC's Ob callback) *and* the plain
read is hooked on top.  So: open one handle per mask, and for each handle try
plain, Ex, and ReadProcessMemory.  First pair that returns bytes is the reader.
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import namehunt as nh

REPORT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "readprobe.txt")
MASKS = [0x1FFFFF, 0x1F0FFF, 0x143A, 0x1410, 0x0410, 0x0438, 0x0010, 0x0400,
         0x1000, 0x0800, 0x0008]

out = []


def p(s=""):
    out.append(s)


def main():
    pid = nh.find_pid(nh.EXE)
    p("exe=%s pid=%s" % (nh.EXE, pid))
    if not pid:
        return 1

    nt_path = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                           "System32", "ntdll.dll")
    ssn_plain, blk = nh.disk_export(nt_path, "NtReadVirtualMemory")
    ssn_ex, blk_ex = nh.disk_export(nt_path, "NtReadVirtualMemoryEx")
    ssn_open, _ = nh.disk_export(nt_path, "NtOpenProcess")
    p("ssn NtReadVirtualMemory=%s  NtReadVirtualMemoryEx=%s  NtOpenProcess=%s"
      % (hex(ssn_plain) if ssn_plain else "?", hex(ssn_ex) if ssn_ex else "?",
         hex(ssn_open) if ssn_open else "?"))

    sysc = nh.Syscall()
    if not ssn_plain:
        p("no SSN -- abort")
        return 1
    rd5 = sysc.stub(ssn_plain)                    # 6-arg form, extra arg ignored
    rd_ex = sysc.stub(ssn_ex) if ssn_ex else None

    # a scratch target: image region of the game, found through a loose handle
    probe = None
    for hq_mask in (0x0410, 0x0400, 0x1000, 0x1F0FFF):
        hq = nh.k32.OpenProcess(hq_mask, False, pid)
        if not hq:
            p("query handle mask %#x: OpenProcess err=%d" % (hq_mask, ctypes.get_last_error()))
            continue
        mbi = nh.MBI()
        addr = 0x10000
        obeseen = 0
        while addr < 0x7FFFFFFEFFFF:
            n = nh.k32.VirtualQueryEx(hq, ctypes.c_void_p(addr),
                                      ctypes.byref(mbi), ctypes.sizeof(mbi))
            if not n:
                p("query handle mask %#x: VirtualQueryEx err=%d at %#x (regions seen %d)"
                  % (hq_mask, ctypes.get_last_error(), addr, obeseen))
                break
            obeseen += 1
            if (mbi.State == nh.MEM_COMMIT and mbi.Type == nh.MEM_IMAGE
                    and (mbi.Protect & 0xFF) in nh.READABLE):
                probe = mbi.BaseAddress
                break
            addr = mbi.BaseAddress + mbi.RegionSize
        nh.k32.CloseHandle(hq)
        if probe:
            p("query handle mask %#x works (%d regions walked)" % (hq_mask, obeseen))
            break
    p("probe address=%s (image region)" % (hex(probe) if probe else "?"))
    if not probe:
        return 1

    p("")
    p("%-10s %-6s %-12s %-12s %-12s %-10s" %
      ("mask", "handle", "rpm", "plain", "ex", "dup->ex"))
    good = []
    for mask in MASKS:
        h = nh.k32.OpenProcess(mask, False, pid)
        if not h:
            p("%#-10x %-6s err=%d" % (mask, "-", ctypes.get_last_error()))
            continue
        got = ctypes.c_size_t(0)
        buf = ctypes.create_string_buffer(0x20)
        ok = nh.k32.ReadProcessMemory(h, ctypes.c_void_p(probe), buf, 0x20,
                                      ctypes.byref(got))
        rpm = "ok" if ok else "err%d" % ctypes.get_last_error()
        got2 = ctypes.c_size_t(0)
        st = rd5(h, ctypes.c_void_p(probe), buf, 0x20, ctypes.byref(got2), 0)
        plain = "%#x/%d" % (st & 0xFFFFFFFF, got2.value)
        ex = "-"
        if rd_ex:
            got3 = ctypes.c_size_t(0)
            st3 = rd_ex(h, ctypes.c_void_p(probe), buf, 0x20, ctypes.byref(got3), 0)
            ex = "%#x/%d" % (st3 & 0xFFFFFFFF, got3.value)
            if st3 == 0 and got3.value:
                good.append(("ex", mask, h))
        if ok or got2.value:
            good.append(("rpm" if ok else "plain", mask, h))

        # duplicate the handle with the rights we want and retry Ex on the clone
        dup = wt.HANDLE()
        dres = "-"
        if nh.k32.DuplicateHandle(nh.k32.GetCurrentProcess(), h,
                                  nh.k32.GetCurrentProcess(), ctypes.byref(dup),
                                  0x1410, False, 0):
            got4 = ctypes.c_size_t(0)
            if rd_ex:
                st4 = rd_ex(dup, ctypes.c_void_p(probe), buf, 0x20,
                            ctypes.byref(got4), 0)
                dres = "%#x/%d" % (st4 & 0xFFFFFFFF, got4.value)
                if st4 == 0 and got4.value:
                    good.append(("dup-ex", mask, dup))
            nh.k32.CloseHandle(dup)
        else:
            dres = "dup err%d" % ctypes.get_last_error()
        p("%#-10x %-6s %-12s %-12s %-12s %-10s" % (mask, hex(h), rpm, plain, ex, dres))
        nh.k32.CloseHandle(h)

    p("")
    p("working combos: %s" % (good if good else "NONE"))
    if good:
        kind, mask, h = good[0]
        got = ctypes.c_size_t(0)
        buf = ctypes.create_string_buffer(0x20)
        if kind in ("ex", "dup-ex") and rd_ex:
            rd_ex(h, ctypes.c_void_p(probe), buf, 0x20, ctypes.byref(got), 0)
        else:
            rd5(h, ctypes.c_void_p(probe), buf, 0x20, ctypes.byref(got), 0)
        p("first bytes via %s/mask %#x: %s" % (kind, mask, buf.raw.hex(" ")))
    return 0


if __name__ == "__main__":
    rc = main()
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    sys.exit(rc)
