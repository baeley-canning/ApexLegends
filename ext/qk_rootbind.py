r"""Bind current process DTB through the real kernel image and process links.

No name-anchor or mouse path, no new driver. Existing GIOV3 MapK reads
physical pages; known ntoskrnl virtual base validates candidate page-table
roots. EPROCESS +0x1d0 PID/+0x1d8 links/+0x338 name/+0x28 DTB are from the
current kernel PDB, not the stale alternate layouts. Fail-closed until the
current PID's Apex PE parses from PEB.ImageBaseAddress.
"""
import ctypes as C
import os
import struct
import time

import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread
import qk_kernelroot
import qk_bridge


def kernel_va():
    n = 1 << 20
    buf = C.create_string_buffer(n)
    need = C.c_ulong()
    st = C.windll.ntdll.NtQuerySystemInformation(11, buf, n, C.byref(need))
    if st == 0xC0000004:
        buf = C.create_string_buffer(need.value + 65536)
        C.windll.ntdll.NtQuerySystemInformation(11, buf, C.sizeof(buf), C.byref(need))
    count = struct.unpack_from("<I", buf.raw, 0)[0]
    for i in range(count):
        o = 8 + 16 + i * 0x128
        base, size = struct.unpack_from("<QQ", buf.raw, o)
        path = buf.raw[o+24:].split(b"\0")[0]
        if path.lower().endswith(b"\\ntoskrnl.exe") and base >> 48 == 0xffff:
            return base
    raise RuntimeError("no live kernel base")


def locate(g, log, budget=180):
    base = kernel_va()
    rva = qk_kernelroot.export_rva(base, b"PsInitialSystemProcess")
    if not rva:
        raise RuntimeError("could not resolve PsInitialSystemProcess")
    psva = base + rva
    pids = qk_bridge.find_pid()
    if not pids:
        log("VERDICT: SKIPPED - no current Apex process")
        return None
    pid = pids[0]
    peb = qk_va._peb_va(pid)
    idx = (base >> 39) & 0x1FF
    log("KERNEL=%#x PSINIT=%#x PID=%d PEB=%#x" % (base, psva, pid, peb))
    start = time.time()
    candidates = 0
    root = 0
    for lo, hi in g.mapread.ranges:
        pa = lo
        while pa + 0x1000 <= hi and time.time() - start < budget:
            try:
                data = g.read_phys(pa, 0x1000)
            except OSError:
                pa += 0x1000
                continue
            if not (struct.unpack_from("<Q", data, idx*8)[0] & 1):
                pa += 0x1000
                continue
            candidates += 1
            try:
                rd = qk_va.Reader(g, pa)
                if rd.read(base, 2) != b"MZ":
                    pa += 0x1000
                    continue
                meta = dl.validate_pe(rd.read(base, 0x1000))
                if not meta:
                    pa += 0x1000
                    continue
                root = pa
                log("ROOT=%#x maps Windows PE, tested=%d time=%.1fs" % (root, candidates, time.time()-start))
                break
            except OSError:
                pass
            pa += 0x1000
        if root:
            break
    if not root:
        log("VERDICT: BLOCKED no root-to-PE proof candidates=%d" % candidates)
        return None
    rd = qk_va.Reader(g, root)
    initial = struct.unpack("<Q", rd.read(psva, 8))[0]
    log("initial EPROCESS=%#x" % initial)
    current = initial
    for _ in range(600):
        if not current or current >> 48 != 0xffff:
            break
        pid2 = struct.unpack("<Q", rd.read(current+0x1d0, 8))[0]
        if pid2 == pid:
            name = rd.read(current+0x338, 15)
            dtb = struct.unpack("<Q", rd.read(current+0x28, 8))[0] & dl.MASK
            log("OBJECT=%#x name=%r DTB=%#x" % (current, name, dtb))
            rr = qk_va.Reader(g, dtb)
            raw = rr.read(peb+0x10, 8)
            if raw:
                ib = struct.unpack("<Q", raw)[0]
                page = rr.read(ib, 0x1000)
                meta = dl.validate_pe(page) if page else None
                if meta and meta["size"] == 0xDFB8000:
                    qk_va.save_cache(pid, dtb, ib)
                    log("RESULT: DTB=%#x base=%#x image_pa=%#x VERIFIED" % (dtb, ib, rr.page_pa(ib)))
                    return dtb, ib
            break
        current = struct.unpack("<Q", rd.read(current+0x1d8, 8))[0]-0x1d8
        if current == initial:
            break
    log("VERDICT: BLOCKED process chain ended without validated Apex PE")
    return None