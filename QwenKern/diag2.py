#!/usr/bin/env python3
"""Deep diagnostic: Python arch, exe path, PEB validity, and the robust
EnumProcessModulesEx/GetModuleInformation alternative."""
import ctypes
import ctypes.wintypes as wt
import struct

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll", use_last_error=True)

print("Python pointer size (8=64bit):", struct.calcsize("P"))
print("c_void_p size:", ctypes.sizeof(ctypes.c_void_p))

PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400
TH32CS_SNAPPROCESS = 0x2
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

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
kernel32.QueryFullProcessImageNameW.argtypes = [wt.HANDLE, wt.DWORD, wt.LPWSTR,
                                                ctypes.POINTER(wt.DWORD)]
kernel32.QueryFullProcessImageNameW.restype = wt.BOOL

NtQueryInformationProcess = ntdll.NtQueryInformationProcess
NtQueryInformationProcess.restype = ctypes.c_long
NtQueryInformationProcess.argtypes = [wt.HANDLE, wt.ULONG, ctypes.c_void_p,
                                      wt.ULONG, ctypes.POINTER(wt.ULONG)]

psapi.EnumProcessModulesEx.argtypes = [wt.HANDLE, ctypes.POINTER(wt.HMODULE),
                                       wt.DWORD, ctypes.POINTER(wt.DWORD), wt.DWORD]
psapi.EnumProcessModulesEx.restype = wt.BOOL
psapi.GetModuleInformation.argtypes = [wt.HANDLE, wt.HMODULE, ctypes.c_void_p,
                                       wt.DWORD]
psapi.GetModuleInformation.restype = wt.BOOL
psapi.GetModuleBaseNameW.argtypes = [wt.HANDLE, wt.HMODULE, wt.LPWSTR, wt.DWORD]
psapi.GetModuleBaseNameW.restype = wt.DWORD


class PBI(ctypes.Structure):
    _fields_ = [("ExitStatus", ctypes.c_long),
                ("PebBaseAddress", ctypes.c_void_p),
                ("AffinityMask", ctypes.c_void_p),
                ("BasePriority", ctypes.c_long),
                ("UniqueProcessId", ctypes.c_void_p),
                ("InheritedFromUniqueProcessId", ctypes.c_void_p)]


class MODULEINFO(ctypes.Structure):
    _fields_ = [("lpBaseOfDll", ctypes.c_void_p),
                ("SizeOfImage", wt.DWORD),
                ("EntryPoint", ctypes.c_void_p)]


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD),
                ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD),
                ("szExeFile", ctypes.c_wchar * 260)]


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


pid = find_process_id("r5apex_dx12.exe")
print("PID:", pid)
handle = kernel32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
print("handle:", hex(handle or 0))

# exe path
buf = ctypes.create_unicode_buffer(1024)
sz = wt.DWORD(1024)
if kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(sz)):
    print("exe path:", buf.value)
else:
    print("QueryFullProcessImageNameW failed err=", ctypes.get_last_error())

# PEB
pbi = PBI()
retlen = wt.ULONG(0)
status = NtQueryInformationProcess(handle, 0, ctypes.byref(pbi),
                                   ctypes.sizeof(PBI), ctypes.byref(retlen))
print("PBI struct size:", ctypes.sizeof(PBI), "NtQIP status:", hex(status & 0xFFFFFFFF))
peb = pbi.PebBaseAddress or 0
print("PEB:", hex(peb))

# Try reading PEB page
if peb:
    for delta in (0, 0x08, 0x10, 0x1000):
        d, e = read_mem(handle, peb + delta, 8)
        print("  PEB+0x%04x -> %s err=%d" % (delta, "OK" if d else "FAIL", e))

# Robust alternative: EnumProcessModulesEx + GetModuleInformation
needed = wt.DWORD(0)
mods = (wt.HMODULE * 1024)()
if psapi.EnumProcessModulesEx(handle, mods, ctypes.sizeof(mods),
                              ctypes.byref(needed), 0x03):  # LIST_MODULES_ALL
    nmods = needed.value // ctypes.sizeof(wt.HMODULE)
    print("EnumProcessModulesEx OK, module count:", nmods)
    for i in range(min(nmods, 5)):
        mi = MODULEINFO()
        if psapi.GetModuleInformation(handle, mods[i], ctypes.byref(mi),
                                      ctypes.sizeof(MODULEINFO)):
            name = ctypes.create_unicode_buffer(260)
            psapi.GetModuleBaseNameW(handle, mods[i], name, 260)
            base = mi.lpBaseOfDll or 0
            print("  mod[%d] base=0x%x size=0x%x name=%s" %
                  (i, base, mi.SizeOfImage, name.value))
            # try read DOS header
            dos, e = read_mem(handle, base, 64)
            print("    read DOS@base: %r err=%d" % (dos[:2] if dos else None, e))
        else:
            print("  GetModuleInformation failed err=", ctypes.get_last_error())
else:
    print("EnumProcessModulesEx FAILED err=", ctypes.get_last_error())

kernel32.CloseHandle(handle)
