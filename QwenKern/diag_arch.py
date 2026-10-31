#!/usr/bin/env python3
"""Correct ctypes diagnostic for the ESP PEB read failure.

Sets proper argtypes/restype on every API so we rule out the ctypes 32-bit
default-int truncation artifact. Determines the real process architecture via
IsWow64Process and reads the PEB at the CORRECT ImageBaseAddress offset
(0x10 for native x64, 0x08 for a 32-bit/WOW64 process).
"""
import ctypes
import ctypes.wintypes as wt

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll", use_last_error=True)

PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400
TH32CS_SNAPPROCESS = 0x2
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

# ---- argtypes/restype setup ----------------------------------------------
kernel32.CreateToolhelp32Snapshot.restype = wt.HANDLE
kernel32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
kernel32.Process32FirstW.argtypes = [wt.HANDLE, ctypes.c_void_p]
kernel32.Process32FirstW.restype = wt.BOOL
kernel32.Process32NextW.argtypes = [wt.HANDLE, ctypes.c_void_p]
kernel32.Process32NextW.restype = wt.BOOL
kernel32.CloseHandle.argtypes = [wt.HANDLE]
kernel32.CloseHandle.restype = wt.BOOL
kernel32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
kernel32.OpenProcess.restype = wt.HANDLE
kernel32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                       ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
kernel32.ReadProcessMemory.restype = wt.BOOL
kernel32.IsWow64Process.argtypes = [wt.HANDLE, ctypes.POINTER(wt.BOOL)]
kernel32.IsWow64Process.restype = wt.BOOL
kernel32.GetLastError.restype = wt.DWORD
kernel32.GetLastError.argtypes = []

# NtQueryInformationProcess
NtQueryInformationProcess = ntdll.NtQueryInformationProcess
NtQueryInformationProcess.restype = ctypes.c_long  # NTSTATUS
NtQueryInformationProcess.argtypes = [wt.HANDLE, wt.ULONG, ctypes.c_void_p,
                                      wt.ULONG, ctypes.POINTER(wt.ULONG)]


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD),
                ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD),
                ("szExeFile", ctypes.c_wchar * 260)]


class PBI(ctypes.Structure):
    _fields_ = [("ExitStatus", ctypes.c_long),
                ("PebBaseAddress", ctypes.c_void_p),
                ("AffinityMask", ctypes.c_void_p),
                ("BasePriority", ctypes.c_long),
                ("UniqueProcessId", ctypes.c_void_p),
                ("InheritedFromUniqueProcessId", ctypes.c_void_p)]


def find_process_id(name):
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
    if not kernel32.ReadProcessMemory(handle, ctypes.c_void_p(addr), buf, size,
                                      ctypes.byref(rd)):
        return None, ctypes.get_last_error()
    return buf.raw, 0


def main():
    pid = find_process_id("r5apex_dx12.exe")
    print("PID:", pid)
    if not pid:
        return

    handle = kernel32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION,
                                  False, pid)
    print("OpenProcess handle:", hex(handle or 0))
    if not handle:
        print("  err", ctypes.get_last_error())
        return

    # Architecture check
    is_wow64 = wt.BOOL(False)
    ok = kernel32.IsWow64Process(handle, ctypes.byref(is_wow64))
    print("IsWow64Process returned:", bool(ok),
          "-> is_wow64(32-bit under WOW64):", bool(is_wow64.value))

    # PEB
    pbi = PBI()
    retlen = wt.ULONG(0)
    status = NtQueryInformationProcess(handle, 0, ctypes.byref(pbi),
                                       ctypes.sizeof(PBI), ctypes.byref(retlen))
    print("NtQueryInformationProcess status: 0x%08x" % (status & 0xFFFFFFFF))
    print("PEB at:", hex(pbi.PebBaseAddress or 0))

    if pbi.PebBaseAddress:
        # Choose the correct offset based on architecture.
        # Native x64 PEB: ImageBaseAddress at +0x10. 32-bit PEB: at +0x08.
        offsets = [0x08, 0x10]
        for off in offsets:
            data, err = read_mem(handle, pbi.PebBaseAddress + off, 8)
            if data is not None:
                ib = int.from_bytes(data, "little")
                print("  PEB+0x%02x = 0x%016x  (read OK)" % (off, ib))
                # Try to read DOS header at that base
                dos, derr = read_mem(handle, ib, 64)
                if dos is not None and dos[:2] == b"MZ":
                    print("    -> DOS header MZ OK at image base")
                else:
                    print("    -> DOS header at base: %r (err=%d)" %
                          (dos[:2] if dos else None, derr))
            else:
                print("  PEB+0x%02x read FAILED err=%d" % (off, err))

    kernel32.CloseHandle(handle)


if __name__ == "__main__":
    main()
