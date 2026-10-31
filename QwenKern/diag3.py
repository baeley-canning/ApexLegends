#!/usr/bin/env python3
"""Definitive checks: exe arch from disk, elevation, and whether ANY read works."""
import ctypes
import ctypes.wintypes as wt
import struct
import os

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll", use_last_error=True)
shell32 = ctypes.WinDLL("shell32", use_last_error=True)

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
kernel32.GetLastError.restype = wt.DWORD
kernel32.GetLastError.argtypes = []
shell32.IsUserAnAdmin.restype = wt.BOOL
shell32.IsUserAnAdmin.argtypes = []

NtQueryInformationProcess = ntdll.NtQueryInformationProcess
NtQueryInformationProcess.restype = ctypes.c_long
NtQueryInformationProcess.argtypes = [wt.HANDLE, wt.ULONG, ctypes.c_void_p,
                                      wt.ULONG, ctypes.POINTER(wt.ULONG)]


class PBI(ctypes.Structure):
    _fields_ = [("ExitStatus", ctypes.c_long),
                ("PebBaseAddress", ctypes.c_void_p),
                ("AffinityMask", ctypes.c_void_p),
                ("BasePriority", ctypes.c_long),
                ("UniqueProcessId", ctypes.c_void_p),
                ("InheritedFromUniqueProcessId", ctypes.c_void_p)]


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


print("IsUserAnAdmin (am I elevated?):", bool(shell32.IsUserAnAdmin()))

# ---- 1) Check exe arch from disk ----
exe = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
print("exe exists:", os.path.exists(exe))
try:
    with open(exe, "rb") as f:
        data = f.read()
    print("exe file size:", len(data))
    e_lfanew = struct.unpack("<I", data[0x3C:0x40])[0]
    nt = data[e_lfanew:e_lfanew + 0x40]
    magic = struct.unpack("<H", nt[0x18:0x1A])[0]
    print("PE magic: 0x%04x -> %s" % (magic,
          "PE32+ (64-bit)" if magic == 0x20B else
          "PE32 (32-bit)" if magic == 0x10B else "UNKNOWN"))
except Exception as ex:
    print("exe parse failed:", ex)

# ---- 2) Process reads ----
pid = find_process_id("r5apex_dx12.exe")
print("PID:", pid)
handle = kernel32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid)
print("handle:", hex(handle or 0))

is_wow64 = wt.BOOL(False)
kernel32.IsWow64Process(handle, ctypes.byref(is_wow64))
print("is_wow64 (32-bit under WOW64):", bool(is_wow64.value))

pbi = PBI()
retlen = wt.ULONG(0)
status = NtQueryInformationProcess(handle, 0, ctypes.byref(pbi),
                                   ctypes.sizeof(PBI), ctypes.byref(retlen))
peb = pbi.PebBaseAddress or 0
print("PEB:", hex(peb))

# Try reading a broad set of candidate addresses to see if ANY read works
candidates = [peb, peb + 0x08, peb + 0x10,
              0x7ffdf000, 0x7ffd0000, 0x10000, 0x400000, 0x140000000,
              0x7ff000000000, 0x3e2000, 0x3e1000]
print("--- probing reads ---")
for addr in candidates:
    d, e = read_mem(handle, addr, 8)
    print("  0x%x -> %s err=%d" % (addr, "OK" if d else "FAIL", e))

kernel32.CloseHandle(handle)
