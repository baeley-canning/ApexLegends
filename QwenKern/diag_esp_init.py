#!/usr/bin/env python3
"""Diagnostic: replicate EntityExtractor::Initialize() to find WHERE it fails.

Mirrors entity_extractor.cpp logic (FindProcessIdByName -> OpenProcess ->
ResolveModuleInfo via PEB -> pattern scan). Reports each step so we can tell
whether the failure is process-not-found, module-read, or pattern-scan.
"""
import ctypes
import ctypes.wintypes as wt
import struct

kernel32 = ctypes.windll.kernel32
ntdll = ctypes.windll.ntdll
user32 = ctypes.windll.user32

PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400
TH32CS_SNAPPROCESS = 0x2
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value


def find_process_id(name):
    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                    ("th32ProcessID", wt.DWORD), ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                    ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                    ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                    ("dwFlags", wt.DWORD), ("szExeFile", ctypes.c_wchar * 260)]
    snap = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snap == INVALID_HANDLE_VALUE:
        return 0
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(PROCESSENTRY32W)
    pid = 0
    if kernel32.Process32FirstW(snap, ctypes.byref(pe)):
        while True:
            if pe.szExeFile.lower() == name.lower():
                pid = pe.th32ProcessID
                break
            if not kernel32.Process32NextW(snap, ctypes.byref(pe)):
                break
    kernel32.CloseHandle(snap)
    return pid


def read_mem(handle, addr, size):
    buf = ctypes.create_string_buffer(size)
    rd = ctypes.c_size_t(0)
    if not kernel32.ReadProcessMemory(handle, ctypes.c_void_p(addr), buf, size, ctypes.byref(rd)):
        return None
    if rd.value != size:
        return None
    return buf.raw


def scan_pattern(base, size, pattern, mask):
    """Naive byte scan; returns offset or 0."""
    pbytes = pattern
    for i in range(size - len(pbytes) + 1):
        ok = True
        for j in range(len(pbytes)):
            if mask[j] == 'x' and base[i + j] != pbytes[j]:
                ok = False
                break
        if ok:
            return i
    return 0


def main():
    print("=== ESP_Initialize diagnostic ===")
    pid = find_process_id("r5apex_dx12.exe")
    if not pid:
        print("[FAIL] r5apex_dx12.exe not found by name")
        return
    print("[OK]   process found: PID", pid)

    handle = kernel32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
    if not handle:
        print("[FAIL] OpenProcess failed err=%d" % kernel32.GetLastError())
        return
    print("[OK]   OpenProcess succeeded")

    # NtQueryInformationProcess -> PEB -> ImageBaseAddress (offset 0x10 on x64)
    class PBI(ctypes.Structure):
        _fields_ = [("ExitStatus", ctypes.c_long),
                    ("PebBaseAddress", ctypes.c_void_p),
                    ("AffinityMask", ctypes.c_void_p),
                    ("BasePriority", ctypes.c_long),
                    ("UniqueProcessId", ctypes.c_void_p),
                    ("InheritedFromUniqueProcessId", ctypes.c_void_p)]
    pbi = PBI()
    retlen = ctypes.c_ulong(0)
    status = ntdll.NtQueryInformationProcess(handle, 0, ctypes.byref(pbi), ctypes.sizeof(PBI), ctypes.byref(retlen))
    if status != 0 or not pbi.PebBaseAddress:
        print("[FAIL] NtQueryInformationProcess status=0x%x" % status)
        return
    print("[OK]   PEB at", hex(pbi.PebBaseAddress))

    image_base_bytes = read_mem(handle, ctypes.c_void_p(pbi.PebBaseAddress).value + 0x10, 8)
    if not image_base_bytes:
        print("[FAIL] could not read PEB->ImageBaseAddress err=%d" % kernel32.GetLastError())
        return
    image_base = struct.unpack("<Q", image_base_bytes)[0]
    if not image_base:
        print("[FAIL] ImageBaseAddress == 0")
        return
    print("[OK]   ImageBaseAddress", hex(image_base))

    dos = read_mem(handle, image_base, 64)
    if not dos or dos[:2] != b"MZ":
        print("[FAIL] DOS header not MZ")
        return
    e_lfanew = struct.unpack("<I", dos[0x3C:0x40])[0]
    nt = read_mem(handle, image_base + e_lfanew, 0x30)
    if not nt:
        print("[FAIL] could not read NT headers")
        return
    sig = struct.unpack("<I", nt[0:4])[0]
    if sig != 0x4550:  # PE\0\0
        print("[FAIL] NT signature not PE")
        return
    magic = struct.unpack("<H", nt[0x18:0x1A])[0]
    if magic != 0x20B:  # IMAGE_NT_OPTIONAL_HDR64_MAGIC
        print("[FAIL] not PE32+ (magic=0x%x)" % magic)
        return
    size_of_image = struct.unpack("<I", nt[0x30:0x34])[0]
    print("[OK]   SizeOfImage", hex(size_of_image))

    # Read the whole image in chunks and scan for the two patterns
    print("[..]   scanning %d bytes for signatures ..." % size_of_image)
    chunk = 0x100000
    base = bytearray()
    addr = image_base
    while len(base) < size_of_image:
        n = min(chunk, size_of_image - len(base))
        data = read_mem(handle, addr, n)
        if data is None:
            print("[FAIL] read failed at 0x%x err=%d" % (addr, kernel32.GetLastError()))
            return
        base += data
        addr += n
    base = bytes(base)

    entity_pat = b"\x48\x8B\x05\x00\x00\x00\x00\x48\x8B\x48\x00"
    entity_mask = "xxx????xxxx"
    local_pat = b"\x48\x8B\x05\x00\x00\x00\x00\x48\x85\xC0"
    local_mask = "xxx????xxxx"

    ent_off = scan_pattern(base, len(base), entity_pat, entity_mask)
    loc_off = scan_pattern(base, len(base), local_pat, local_mask)
    print("[%s] entity_list pattern offset = 0x%x" % ("OK" if ent_off else "FAIL", ent_off))
    print("[%s] local_player pattern offset = 0x%x" % ("OK" if loc_off else "FAIL", loc_off))

    if ent_off and loc_off:
        print("\n[RESULT] Both patterns found -> Initialize() should SUCCEED")
    else:
        print("\n[RESULT] One or both patterns missing -> Initialize() returns false")
        print("        This is the root cause: hardcoded signatures don't match this Apex build.")


if __name__ == "__main__":
    main()
