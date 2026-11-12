# ============================================================================
# _ritual\ov62_entrystub_inject.ps1 - create r5apex_dx12.exe with
# CREATE_SUSPENDED, then *stub its entry point*: write a 42-byte shellcode that
# calls LoadLibraryW(payload) and jumps to the real entry, patch the entry with
# an absolute jump to it, resume.
#
# Why (measured, ov61): alloc/write/create-remote-thread all succeed while the
# process is suspended (VirtualAllocEx=5 is gone - the jail is confirmed to be
# armed at image init, not at creation), but a remote LoadLibraryW faults
# (0xC0000005) because loader init has not run yet, and the process then dies on
# resume.  The entry stub gets the payload in *after* loader init but *before*
# the game's own entry code runs, and LoadLibrary then runs in-process, where
# EAAC's jail cannot reach it.
#
# Variable that differs from ov61: entry-point stub instead of a remote
# LoadLibrary thread.  Read-back: alloc, write, header parse, patched entry
# bytes re-read and compared, module base, alive, window.  Restore: process is
# terminated on failure (patch dies with it); nothing persistent is touched.
# ============================================================================
param([string] $Exe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe',
      [string] $Dll = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat.dll',
      [int] $Attempts = 3, [int] $HoldSec = 0, [switch] $VerifyOnly, [switch] $NoPatch, [switch] $NoUnicodeEnv, [switch] $NoSuspend)

$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'ov63_run.out'
$logDir = Join-Path $env:LOCALAPPDATA 'QwenKern'
function W([string] $s) { [IO.File]::AppendAllText($out, $s + "`r`n"); Write-Host $s }
function Finish([string] $verdict, [int] $code) { W "RESULT: $verdict"; W "ov63 DONE $verdict"; exit $code }

[IO.File]::WriteAllText($out, ('ov63 - verify-only (restore+jmp, no LoadLibrary) - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"))
W "target  : $Exe"
W "payload : $Dll ($((Get-Item -LiteralPath $Dll).Length) bytes)"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    W 'not elevated -> relaunching self as admin'
    $extra = ''
    if ($VerifyOnly) { $extra += ' -VerifyOnly' }
    if ($NoPatch) { $extra += ' -NoPatch' }
    if ($NoUnicodeEnv) { $extra += ' -NoUnicodeEnv' }
    if ($NoSuspend) { $extra += ' -NoSuspend' }
    $extra += " -Attempts $Attempts"
    if ($HoldSec -gt 0) { $extra += " -HoldSec $HoldSec" }
    Start-Process powershell -Verb RunAs -ArgumentList (
        ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $PSCommandPath, $extra))
    exit 0
}
W 'elevated: True'

# we are elevated: EAAC denies TerminateProcess to unelevated callers, so the
# old instance is killed here (verified) instead of asking the user to exit.
for ($k = 1; $k -le 6; $k++) {
    $p = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)
    if ($p.Count -eq 0) { break }
    foreach ($x in $p) { W ("kill     : pid={0} -> {1}" -f $x.Id, ((taskkill /F /T /PID $x.Id 2>&1) -join ' ')) }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)) { break }
    }
}
if (@(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count -ne 0) {
    Finish 'FAIL game-will-not-die' 1
}
W 'game     : none running'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sp64 {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId;
    }
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr OpenProcess(uint acc, bool inh, int pid);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, IntPtr size, uint type, uint prot);
    [DllImport("kernel32", SetLastError = true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern bool VirtualProtectEx(IntPtr hp, IntPtr addr, IntPtr size, uint prot, out uint old);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr GetProcAddress(IntPtr mod, string name);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr CreateRemoteThread(IntPtr hp, IntPtr sa, IntPtr stack, IntPtr start, IntPtr param, uint flags, out int tid);
    [DllImport("kernel32", SetLastError = true)] public static extern uint ResumeThread(IntPtr ht);
    [DllImport("kernel32", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError = true)] public static extern bool GetExitCodeThread(IntPtr ht, out IntPtr code);
    [DllImport("kernel32", SetLastError = true)] public static extern bool TerminateProcess(IntPtr hp, uint code);
    [DllImport("kernel32", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr CreateToolhelp32Snapshot(uint flags, int pid);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MODULEENTRY32W {
        public int dwSize; public int th32ModuleID; public int th32ProcessID; public int GlblcntUsage;
        public int ProccntUsage; public IntPtr modBaseAddr; public int modBaseSize; public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExePath;
    }
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool Module32FirstW(IntPtr snap, ref MODULEENTRY32W me);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool Module32NextW(IntPtr snap, ref MODULEENTRY32W me);

    public const uint CREATE_SUSPENDED = 0x00000004, CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    public const uint ALL = 0x1F0FFF, MEM_COMMIT_RESERVE = 0x3000, PAGE_RWX = 0x40;

    [DllImport("kernel32", SetLastError = true)] public static extern bool GetExitCodeProcess(IntPtr hp, out uint code);

    public static long ModuleBase(int pid, string name) {
        IntPtr snap = CreateToolhelp32Snapshot(0x8, pid);
        if (snap == (IntPtr)(-1)) return 0;
        MODULEENTRY32W me = new MODULEENTRY32W(); me.dwSize = Marshal.SizeOf(typeof(MODULEENTRY32W));
        bool ok = Module32FirstW(snap, ref me);
        long found = 0;
        while (ok) {
            if (string.Equals(me.szModule, name, StringComparison.OrdinalIgnoreCase)) { found = me.modBaseAddr.ToInt64(); break; }
            ok = Module32NextW(snap, ref me);
        }
        CloseHandle(snap);
        return found;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct MBI {
        public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect, a1;
        public IntPtr RegionSize; public uint State, Protect, Type, a2;
    }
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr VirtualQueryEx(IntPtr hp, IntPtr addr, out MBI mbi, IntPtr len);

    // first MEM_IMAGE carrying a valid PE32+ header = the main exe (loader-independent)
    public static long FindImageBase(IntPtr hp) {
        long addr = 0x10000;
        MBI m;
        IntPtr len = (IntPtr)Marshal.SizeOf(typeof(MBI));
        while (addr > 0 && addr < 0x7FFFFFFF0000L) {
            if (VirtualQueryEx(hp, (IntPtr)addr, out m, len) == IntPtr.Zero) { addr += 0x10000; continue; }
            long rs = m.RegionSize.ToInt64();
            if (rs <= 0) break;
            if (m.State == 0x1000 && m.Type == 0x1000000) {
                byte[] h = new byte[0x200]; IntPtr got;
                if (ReadProcessMemory(hp, m.BaseAddress, h, (IntPtr)h.Length, out got)
                    && h[0] == 0x4D && h[1] == 0x5A) {
                    int lf = BitConverter.ToInt32(h, 0x3C);
                    if (lf > 0 && lf < 0x1F0 && BitConverter.ToUInt32(h, lf) == 0x00004550
                        && BitConverter.ToUInt16(h, lf + 24) == 0x20B)
                        return m.BaseAddress.ToInt64();
                }
            }
            addr = m.BaseAddress.ToInt64() + rs;
        }
        return 0;
    }
}
'@

$dllName = Split-Path $Dll -Leaf

# stale logs of dead pids read as success on a recycled pid
foreach ($f in @(Get-ChildItem $logDir -Filter 'payload_*.log' -ErrorAction SilentlyContinue)) {
    $n = 0
    if ([int]::TryParse(($f.BaseName -replace '^payload_', ''), [ref] $n)) {
        if (-not (Get-Process -Id $n -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

# one-time disk parse of the image header: invariant across attempts, and it
# used to run inside the CreateProcessW..ResumeThread window
$img = [IO.File]::ReadAllBytes($Exe)
$lf = [BitConverter]::ToInt32($img, 0x3C)
W "header   : parsed once, e_lfanew=0x$($lf.ToString('X')) ($([math]::Round($img.Length / 1MB, 1)) MB)"


for ($a = 1; $a -le $Attempts; $a++) {
    W "attempt $a/$Attempts"
    $t0 = Get-Date
    $si = New-Object 'Sp64+STARTUPINFO'
    $si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)
    $si.lpDesktop = 'WinSta0\Default'
    $pi = New-Object 'Sp64+PROCESS_INFORMATION'
    $cwd = Split-Path $Exe -Parent

    $pFlags = 0
    if (-not $NoSuspend) { $pFlags = $pFlags -bor [Sp64]::CREATE_SUSPENDED }
    if (-not $NoUnicodeEnv) { $pFlags = $pFlags -bor [Sp64]::CREATE_UNICODE_ENVIRONMENT }
    W "flags    : 0x$($pFlags.ToString('X'))"
    if (-not [Sp64]::CreateProcessW($Exe, "`"$Exe`"", [IntPtr]::Zero, [IntPtr]::Zero, $false,
                                   $pFlags, [IntPtr]::Zero, $cwd, [ref] $si, [ref] $pi)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: CreateProcessW err=$e"
        if ($a -eq $Attempts) { Finish "FAIL CreateProcessW=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    W "created SUSPENDED pid=$($pi.dwProcessId) hproc=$($pi.hProcess) hthread=$($pi.hThread)"
    $tCreate = Get-Date

    $hp = [Sp64]::OpenProcess([Sp64]::ALL, $false, $pi.dwProcessId)
    if ($hp -eq [IntPtr]::Zero) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: OpenProcess err=$e (suspended - this must never be a jail)"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL OpenProcess=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }

    $bytes = [Text.Encoding]::Unicode.GetBytes($Dll + "`0")
    $mem = [Sp64]::VirtualAllocEx($hp, [IntPtr]::Zero, [IntPtr] $bytes.Length, [Sp64]::MEM_COMMIT_RESERVE, [Sp64]::PAGE_RWX)
    if ($mem -eq [IntPtr]::Zero) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: VirtualAllocEx err=$e  <-- the variable under test"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL VirtualAllocEx=$e (even suspended)" 1 }
        Start-Sleep -Seconds 3; continue
    }
    W "alloc    : 0x$($mem.ToString('X')) ($($bytes.Length) B unicode path)"

    $done = [IntPtr]::Zero
    if (-not [Sp64]::WriteProcessMemory($hp, $mem, $bytes, [IntPtr] $bytes.Length, [ref] $done)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: WriteProcessMemory err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL WriteProcessMemory=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    W "write    : ok ($done B)"

    $k32 = [Sp64]::GetModuleHandleW('kernel32.dll')
    $ll = if ($k32 -ne [IntPtr]::Zero) { [Sp64]::GetProcAddress($k32, 'LoadLibraryW') } else { [IntPtr]::Zero }
    $tid = 0
    W "k32      : 0x$($k32.ToString('X')) LoadLibraryW=0x$($ll.ToString('X'))"
    if ($ll -eq [IntPtr]::Zero) {
        W 'FAIL: LoadLibraryW unresolved in the parent'
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish 'FAIL ll-unresolved' 1 }
        Start-Sleep -Seconds 3; continue
    }

    # ---- entry RVA from the on-disk header (validated), base from memory -----
    # ($img/$lf were parsed once before the loop: reading a 234 MB exe between
    #  CreateProcessW and ResumeThread kept the process suspended for hundreds
    #  of ms - the newest suspect for the 0x186AA abort)
    if ([BitConverter]::ToUInt32($img, $lf) -ne 0x00004550) {
        W 'FAIL: disk PE signature mismatch'; [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish 'FAIL bad-pe-header' 1 }
        Start-Sleep -Seconds 3; continue
    }
    $opt = $lf + 24
    $entryRva = [BitConverter]::ToUInt32($img, $opt + 16)
    $sizeImg = [BitConverter]::ToUInt32($img, $opt + 56)
    $base = [Sp64]::FindImageBase($hp)
    if ($base -eq 0) {
        W 'FAIL: no PE image found in address space'
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish 'FAIL image-base-not-found' 1 }
        Start-Sleep -Seconds 3; continue
    }
    $entry = [IntPtr] ($base + $entryRva)
    W "image    : base=0x$($base.ToString('X')) entryRva=0x$($entryRva.ToString('X')) -> entry=0x$($entry.ToString('X')) sizeOfImage=0x$($sizeImg.ToString('X'))"
    if ($entryRva -eq 0 -or $entryRva -ge $sizeImg) {
        W 'FAIL: entry RVA implausible'; [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish 'FAIL entry-rva-implausible' 1 }
        Start-Sleep -Seconds 3; continue
    }

    # identity check: the header in memory must be the same image as the file
    $mh = New-Object byte[] 0x200
    $done2 = [IntPtr]::Zero
    if (-not [Sp64]::ReadProcessMemory($hp, [IntPtr] $base, $mh, [IntPtr] 0x200, [ref] $done2)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: cannot read image header err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL read-image-header=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    $mEntry = [BitConverter]::ToUInt32($mh, $lf + 24 + 16)
    $mStamp = [BitConverter]::ToUInt32($mh, $lf + 8)
    $dStamp = [BitConverter]::ToUInt32($img, $lf + 8)
    W "identity : memEntryRva=0x$($mEntry.ToString('X')) stamp=0x$($mStamp.ToString('X')) disk=0x$($dStamp.ToString('X'))"
    if ($mEntry -ne $entryRva -or $mStamp -ne $dStamp) {
        W 'FAIL: memory image is not the file image'
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish 'FAIL wrong-image-base' 1 }
        Start-Sleep -Seconds 3; continue
    }

    # ---- stub + entry patch (skipped entirely with -NoPatch) -----------------
    if (-not $NoPatch) {
    # ---- stub: sub rsp,28 | rcx=path | call LoadLibraryW | add rsp,28 |
    #           rcx=12 | rsi=orig12 | rdi=entry | rep movsb | jmp entry
    # The original 12 entry bytes are saved into the stub page so the stub can
    # put them back before jumping (otherwise the jmp would land on our own
    # patch again).  Page is E/RW (VirtualProtectEx below) so the copy succeeds.
    $orig = New-Object byte[] 12
    $done = [IntPtr]::Zero
    if (-not [Sp64]::ReadProcessMemory($hp, $entry, $orig, [IntPtr] 12, [ref] $done)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: ReadProcessMemory(orig entry) err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL read-orig-entry=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    W "orig12   : $(($orig | ForEach-Object { $_.ToString('X2') }) -join ' ')"

    $stubAddr = [IntPtr] ($mem.ToInt64() + 0x100)
    $origAddr = [IntPtr] ($mem.ToInt64() + 0x180)
    $markAddr = [IntPtr] ($mem.ToInt64() + 0x1F0)
    $s = New-Object System.Collections.Generic.List[byte]
    # first thing the stub does: leave a marker byte, so a post-mortem read
    # proves whether the patched entry was ever executed
    $s.AddRange([byte[]]@(0x48, 0xB9)); $s.AddRange([BitConverter]::GetBytes($markAddr.ToInt64()))
    $s.AddRange([byte[]]@(0xC6, 0x01, 0xFF))
    $s.AddRange([byte[]]@(0x48, 0x83, 0xEC, 0x28))
    if (-not $VerifyOnly) {
        $s.AddRange([byte[]]@(0x48, 0xB9)); $s.AddRange([BitConverter]::GetBytes($mem.ToInt64()))
        $s.AddRange([byte[]]@(0x48, 0xB8)); $s.AddRange([BitConverter]::GetBytes($ll.ToInt64()))
        $s.AddRange([byte[]]@(0xFF, 0xD0))
        # second marker after the call: 0xAA = LoadLibraryW returned
        $s.AddRange([byte[]]@(0x48, 0xB9)); $s.AddRange([BitConverter]::GetBytes(($markAddr.ToInt64() + 1)))
        $s.AddRange([byte[]]@(0xC6, 0x01, 0xAA))
    }
    $s.AddRange([byte[]]@(0x48, 0x83, 0xC4, 0x28))
    $s.AddRange([byte[]]@(0x48, 0xC7, 0xC1, 0x0C, 0x00, 0x00, 0x00))
    $s.AddRange([byte[]]@(0x48, 0xBE)); $s.AddRange([BitConverter]::GetBytes($origAddr.ToInt64()))
    $s.AddRange([byte[]]@(0x48, 0xBF)); $s.AddRange([BitConverter]::GetBytes([int64]$entry.ToInt64()))
    $s.AddRange([byte[]]@(0xF3, 0xA4))
    $s.AddRange([byte[]]@(0x48, 0xB8)); $s.AddRange([BitConverter]::GetBytes([int64]$entry.ToInt64()))
    $s.AddRange([byte[]]@(0xFF, 0xE0))
    $stub = $s.ToArray()
    if (-not [Sp64]::WriteProcessMemory($hp, $stubAddr, $stub, [IntPtr] $stub.Length, [ref] $done)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: WriteProcessMemory(stub) err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL write-stub=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    if (-not [Sp64]::WriteProcessMemory($hp, $origAddr, $orig, [IntPtr] 12, [ref] $done)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: WriteProcessMemory(orig12) err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL write-orig12=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    W "stub     : 0x$($stubAddr.ToString('X')) ($($stub.Length) B, LoadLibraryW=0x$($ll.ToString('X')) orig at 0x$($origAddr.ToString('X')))"

    # ---- patch entry: mov rax,stub ; jmp rax  (12 B) -------------------------
    $patch = New-Object System.Collections.Generic.List[byte]
    $patch.AddRange([byte[]]@(0x48, 0xB8)); $patch.AddRange([BitConverter]::GetBytes($stubAddr.ToInt64()))
    $patch.AddRange([byte[]]@(0xFF, 0xE0))
    $pa = $patch.ToArray()
    $oldProt = 0
    if (-not [Sp64]::VirtualProtectEx($hp, $entry, [IntPtr] $pa.Length, 0x40, [ref] $oldProt)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: VirtualProtectEx err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL protect-entry=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    if (-not [Sp64]::WriteProcessMemory($hp, $entry, $pa, [IntPtr] $pa.Length, [ref] $done)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: WriteProcessMemory(entry) err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL patch-entry=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }

    # read-back is the verdict (R3): entry must now hold exactly our jump
    $rb = New-Object byte[] $pa.Length
    $null = [Sp64]::ReadProcessMemory($hp, $entry, $rb, [IntPtr] $rb.Length, [ref] $done)
    $rbHex = ($rb | ForEach-Object { $_.ToString('X2') }) -join ' '
    $paHex = ($pa | ForEach-Object { $_.ToString('X2') }) -join ' '
    W "entry    : readback=$rbHex (oldProt=0x$($oldProt.ToString('X')))"
    if ($rbHex -ne $paHex) {
        W 'FAIL: entry read-back differs from patch'
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish 'FAIL entry-readback-mismatch' 1 }
        Start-Sleep -Seconds 3; continue
    }
    W 'entry    : verified patched'

    } else { W 'nopatch  : entry left untouched (control)' }

    if ($NoSuspend) {
        $suspMs = 0
        W 'resume   : skipped (process was not suspended)'
    } else {
        $resume = [Sp64]::ResumeThread($pi.hThread)
        $suspMs = [int]((Get-Date) - $tCreate).TotalMilliseconds
        W "resume   : previous suspend count=$resume (suspended for $suspMs ms)"
    }

    # tight window: watch the stub markers while the process is still up
    $mark = 0; $mark2 = 0
    if ($markAddr) {
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Milliseconds 5
            if (-not (Get-Process -Id $pi.dwProcessId -ErrorAction SilentlyContinue)) { break }
            $o = [IntPtr]::Zero
            $mk = New-Object byte[] 2
            if ([Sp64]::ReadProcessMemory($hp, $markAddr, $mk, [IntPtr] 2, [ref] $o)) {
                $mark = $mk[0]; $mark2 = $mk[1]
                if ($mark -ne 0) { break }
            }
        }
        W "marker   : 0x$($mark.ToString('X2'))/0x$($mark2.ToString('X2')) at ~$($i * 5) ms (FF=stub ran, AA=LoadLibrary returned)"
    }
    $base = 0; $fresh = $false; $alive = $true
    $logPath = Join-Path $logDir ("payload_{0}.log" -f $pi.dwProcessId)
    for ($w = 0; $w -lt 24; $w++) {
        Start-Sleep -Milliseconds 500
        $alive = [bool](Get-Process -Id $pi.dwProcessId -ErrorAction SilentlyContinue)
        if (-not $alive) { break }
        if ($w -ge 3) {
            $base = [Sp64]::ModuleBase($pi.dwProcessId, $dllName)
            $fresh = (Test-Path -LiteralPath $logPath) -and ((Get-Item -LiteralPath $logPath).LastWriteTime -gt $t0)
            if (-not $VerifyOnly -and ($base -ne 0 -or $fresh)) { break }
        }
    }
    $bTxt = if ($base) { '0x' + $base.ToString('X') } else { '0' }
    W "after    : alive=$alive moduleBase=$bTxt payloadLog=$fresh (waited $([math]::Round(($w + 1) * 0.5, 1)) s)"

    # in verify-only the stub must have put the original bytes back by now
    if ($VerifyOnly -and $alive -and $orig) {
        $nb = New-Object byte[] 12
        $null = [Sp64]::ReadProcessMemory($hp, $entry, $nb, [IntPtr] 12, [ref] $done)
        $nbHex = ($nb | ForEach-Object { $_.ToString('X2') }) -join ' '
        $oHex = ($orig | ForEach-Object { $_.ToString('X2') }) -join ' '
        W "restored : entry=$nbHex orig=$oHex stubRan=$($nbHex -eq $oHex)"
    }

    if (-not $alive) {
        $ec = 0
        $null = [Sp64]::GetExitCodeProcess($pi.hProcess, [ref] $ec)
        W ("process died after resume, exitCode=0x{0:X8} ({1})" -f $ec, $(if ($ec -eq 0xC0000005) { 'AV - our stub/fault' } elseif ($ec -eq 0) { 'exit 0' } else { 'not an AV' }))
        # post-mortem: our handle keeps the address space alive after exit
        if ($markAddr) {
            $o = [IntPtr]::Zero
            $mk = New-Object byte[] 1
            $null = [Sp64]::ReadProcessMemory($hp, $markAddr, $mk, [IntPtr] 1, [ref] $o)
            $eb = New-Object byte[] 12
            $null = [Sp64]::ReadProcessMemory($hp, $entry, $eb, [IntPtr] 12, [ref] $o)
            W ("post     : marker=0x{0:X2} (0xFF=stub ran) entryNow={1}" -f $mk[0], (($eb | ForEach-Object { $_.ToString('X2') }) -join ' '))
        }
        if ($a -eq $Attempts) { Finish ("FAIL process-died exit=0x{0:X8}" -f $ec) 1 }
        continue
    }
    $ok = if ($VerifyOnly) { $true } else { ($base -ne 0) -or $fresh }
    if ($ok) {
        W "PASS: stub mechanism survived pid=$($pi.dwProcessId) (moduleBase=$bTxt log=$fresh)"
        if ($HoldSec -gt 0) { Start-Sleep -Seconds $HoldSec }
        Finish "PASS stub-ok pid=$($pi.dwProcessId)" 0
    }
    W 'no module and no payload log - attempt failed'
    if ($a -eq $Attempts) {
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        Finish 'FAIL injected-but-inert' 1
    }
    Start-Sleep -Seconds 2
}
Finish 'FAIL attempts-exhausted' 1
