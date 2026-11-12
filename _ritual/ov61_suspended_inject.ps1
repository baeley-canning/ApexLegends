# ============================================================================
# _ritual\ov61_suspended_inject.ps1 - create r5apex_dx12.exe ourselves with
# CREATE_SUSPENDED, LoadLibrary the payload into it while *no thread has run*,
# then resume.  Rationale (measured): every usermode rung gets VirtualAllocEx=5
# as soon as the process exists, because EAAC arms its handle jail at image
# init.  A suspended process has not run init yet, so alloc must be allowed -
# this is the only usermode way to be earlier than "early".
#
# Variable that differs from ov60: the *creator* of the process (we are) and
# CREATE_SUSPENDED.  Same payload, same read-back.
#
# Read-back (R3): pid, alloc address, write rc, thread rc, LoadLibrary exit
# code, module base at +2 s, alive, window.  Restore (R4): a failed attempt is
# terminated by us; the payload dies with the process.  Re-runnable: an attempt
# is a complete unit and stale logs of dead pids are purged.
# ============================================================================
param([string] $Exe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe',
      [string] $Dll = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat.dll',
      [int] $Attempts = 3, [int] $HoldSec = 0)

$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'ov61_run.out'
$logDir = Join-Path $env:LOCALAPPDATA 'QwenKern'
function W([string] $s) { [IO.File]::AppendAllText($out, $s + "`r`n"); Write-Host $s }
function Finish([string] $verdict, [int] $code) { W "RESULT: $verdict"; W "ov61 DONE $verdict"; exit $code }

[IO.File]::WriteAllText($out, ('ov61 - suspended-create inject - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"))
W "target  : $Exe"
W "payload : $Dll ($((Get-Item -LiteralPath $Dll).Length) bytes)"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    W 'not elevated -> relaunching self as admin'
    Start-Process powershell -Verb RunAs -ArgumentList (
        '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
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
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr GetModuleHandleW(string name);
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

    public const uint CREATE_SUSPENDED = 0x00000004;
    public const uint ALL = 0x1F0FFF, MEM_COMMIT_RESERVE = 0x3000, PAGE_RW = 0x04;

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

for ($a = 1; $a -le $Attempts; $a++) {
    W "attempt $a/$Attempts"
    $t0 = Get-Date
    $si = New-Object 'Sp64+STARTUPINFO'
    $si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)
    $si.lpDesktop = 'WinSta0\Default'
    $pi = New-Object 'Sp64+PROCESS_INFORMATION'
    $cwd = Split-Path $Exe -Parent

    if (-not [Sp64]::CreateProcessW($Exe, "`"$Exe`"", [IntPtr]::Zero, [IntPtr]::Zero, $false,
                                   [Sp64]::CREATE_SUSPENDED, [IntPtr]::Zero, $cwd, [ref] $si, [ref] $pi)) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: CreateProcessW err=$e"
        if ($a -eq $Attempts) { Finish "FAIL CreateProcessW=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    W "created SUSPENDED pid=$($pi.dwProcessId) hproc=$($pi.hProcess) hthread=$($pi.hThread)"

    $hp = [Sp64]::OpenProcess([Sp64]::ALL, $false, $pi.dwProcessId)
    if ($hp -eq [IntPtr]::Zero) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: OpenProcess err=$e (suspended - this must never be a jail)"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL OpenProcess=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }

    $bytes = [Text.Encoding]::Unicode.GetBytes($Dll + "`0")
    $mem = [Sp64]::VirtualAllocEx($hp, [IntPtr]::Zero, [IntPtr] $bytes.Length, [Sp64]::MEM_COMMIT_RESERVE, [Sp64]::PAGE_RW)
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
    $ll = [Sp64]::GetProcAddress($k32, 'LoadLibraryW')
    $tid = 0
    $ht = [Sp64]::CreateRemoteThread($hp, [IntPtr]::Zero, [IntPtr]::Zero, $ll, $mem, 0, [ref] $tid)
    if ($ht -eq [IntPtr]::Zero) {
        $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "FAIL: CreateRemoteThread err=$e"
        [Sp64]::TerminateProcess($pi.hProcess, 0) | Out-Null
        if ($a -eq $Attempts) { Finish "FAIL CreateRemoteThread=$e" 1 }
        Start-Sleep -Seconds 3; continue
    }
    W "thread   : tid=$tid"
    $wr = [Sp64]::WaitForSingleObject($ht, 20000)
    $code = [IntPtr]::Zero
    [Sp64]::GetExitCodeThread($ht, [ref] $code) | Out-Null
    W "wait     : $wr exit=$($code.ToInt64()) (0x$($code.ToInt64().ToString('X')))"

    $resume = [Sp64]::ResumeThread($pi.hThread)
    W "resume   : previous suspend count=$resume"
    Start-Sleep -Seconds 2

    $alive = [bool](Get-Process -Id $pi.dwProcessId -ErrorAction SilentlyContinue)
    $base = [Sp64]::ModuleBase($pi.dwProcessId, $dllName)
    $logPath = Join-Path $logDir ("payload_{0}.log" -f $pi.dwProcessId)
    $fresh = (Test-Path -LiteralPath $logPath) -and ((Get-Item -LiteralPath $logPath).LastWriteTime -gt $t0)
    $bTxt = if ($base) { '0x' + $base.ToString('X') } else { '0' }
    W "after 2s : alive=$alive moduleBase=$bTxt payloadLog=$fresh"

    if (-not $alive) {
        W 'process died after resume'
        if ($a -eq $Attempts) { Finish 'FAIL process-died-after-resume' 1 }
        continue
    }
    if ($base -ne 0 -or $fresh) {
        W "PASS: payload present in pid=$($pi.dwProcessId)"
        if ($HoldSec -gt 0) { Start-Sleep -Seconds $HoldSec }
        Finish ("PASS injected pid=$($pi.dwProcessId) base=$bTxt") 0
    }
    W 'no module and no payload log - attempt failed'
    if ($a -eq $Attempts) { Finish 'FAIL injected-but-inert' 1 }
    Start-Sleep -Seconds 2
}
Finish 'FAIL attempts-exhausted' 1
