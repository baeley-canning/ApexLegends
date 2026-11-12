# ============================================================================
# _ritual\ov68_liveattach.ps1 - inject into the LIVE, EA-launched game.
#
# WHAT THE PROBES ESTABLISHED (t932..t934, h321..h323, ov65..ov67):
#   * every direct CreateProcessW of r5apex_dx12.exe dies with 0x186AA within
#     0.5 s - suspended or not, elevated or not, patched or not.  ov67 proved
#     CREATE_SUSPENDED is not the trigger.
#   * the process that survives is the one EA's own infra spawns
#     (ppid = EA GameService, empty command line).  Ours is always a straggler.
#   * PROC_THREAD_ATTRIBUTE_PARENT_PROCESS is refused system-wide here
#     (err=50, every parent, every mask, elevated too) - the parent-spoof route
#     in ov65 is dead, not merely unapplied.
#   * that surviving game is EAAC-protected *by integrity level*: from a medium
#     shell only QUERY_LIMITED_INFORMATION + SYNCHRONIZE are granted, but from an
#     elevated token (h323) OpenProcess(ALL_ACCESS) is GRANTED.
#
# So: stop creating.  Take the live EA-launched process and load the payload
# into it with the handles the elevated token grants.
#
# Variable: attach target (live EA process) + a plain LoadLibraryW remote
# thread.  Nothing is created, nothing is suspended, nothing is terminated.
# Reversibility: -Eject unloads with a remote FreeLibrary; otherwise the next
# game exit takes the module with it.
# ============================================================================
param([int] $Pid0 = 0,
      [string] $Dll = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat.dll',
      [int] $HoldSec = 12, [switch] $Eject, [switch] $Elevate)

$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'ov68_run.out'
$logDir = Join-Path $env:LOCALAPPDATA 'QwenKern'
function W([string] $s) { [IO.File]::AppendAllText($out, $s + "`r`n"); Write-Host $s }
function Finish([string] $verdict, [int] $code) { W "RESULT: $verdict"; W "ov68 DONE $verdict"; exit $code }

[IO.File]::WriteAllText($out, ('ov68 - live attach into the EA-launched game - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"))

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    W 'not elevated but -Elevate given -> relaunching self as admin'
    $extra = ' -Elevate'
    if ($Pid0 -gt 0) { $extra += " -Pid0 $Pid0" }
    if ($Eject) { $extra += ' -Eject' }
    $extra += " -HoldSec $HoldSec"
    Start-Process powershell -Verb RunAs -ArgumentList (
        ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $PSCommandPath, $extra))
    exit 0
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sp68 {
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr OpenProcess(uint acc, bool inh, int pid);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, IntPtr size, uint type, uint prot);
    [DllImport("kernel32", SetLastError = true)] public static extern bool VirtualFreeEx(IntPtr hp, IntPtr addr, IntPtr size, uint type);
    [DllImport("kernel32", SetLastError = true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr GetProcAddress(IntPtr mod, string name);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr CreateRemoteThread(IntPtr hp, IntPtr sa, IntPtr stack, IntPtr start, IntPtr param, uint flags, out int tid);
    [DllImport("kernel32", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError = true)] public static extern bool GetExitCodeThread(IntPtr ht, out IntPtr code);
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
    public const uint ALL = 0x1F0FFF, MEM_COMMIT_RESERVE = 0x3000, PAGE_RWX = 0x40, MEM_RELEASE = 0x8000;

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

W "elevated: $isAdmin"
W "payload : $Dll ($((Get-Item -LiteralPath $Dll).Length) bytes)"


# ---- pre-state (R3) --------------------------------------------------------
$all = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)
W "games    : $(($all | ForEach-Object { $_.Id }) -join ',')"
$t = if ($Pid0 -gt 0) { $all | Where-Object { $_.Id -eq $Pid0 } | Select-Object -First 1 }
     else { $all | Sort-Object StartTime | Select-Object -First 1 }
if (-not $t) { Finish 'FAIL no-live-game start the game through EA Desktop first' 1 }
$procId = $t.Id
$ci = Get-CimInstance Win32_Process -Filter "ProcessId=$procId"
W "target   : pid=$procId ppid=$($ci.ParentProcessId) started=$($t.StartTime)"
W "pre      : moduleBase(apexcheat)=0x$(([Sp68]::ModuleBase($procId, $dllName)).ToString('X'))"
$logPath = Join-Path $logDir ("payload_{0}.log" -f $procId)
if (Test-Path -LiteralPath $logPath) {
    W "pre      : stale payload log $((Get-Item -LiteralPath $logPath).LastWriteTime)"
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
}

# ---- handle: this is the variable the whole probe rests on ------------------
$hp = [Sp68]::OpenProcess([Sp68]::ALL, $false, $procId)
if ($hp -eq [IntPtr]::Zero) {
    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    W "FAIL: OpenProcess(ALL) err=$e  <-- elevated? see h323"
    Finish "FAIL openprocess=$e" 1
}
W "handle   : OpenProcess(ALL) ok hproc=$hp"

# ---- resolve remote LoadLibraryW (kernel32 sits at one base for all) -------
$k32 = [Sp68]::GetModuleHandleW('kernel32.dll')
$ll = [Sp68]::GetProcAddress($k32, 'LoadLibraryW')

# ---- write the DLL path into the target -----------------------------------
$bytes = [Text.Encoding]::Unicode.GetBytes($Dll + "`0")
$mem = [Sp68]::VirtualAllocEx($hp, [IntPtr]::Zero, [IntPtr] $bytes.Length, [Sp68]::MEM_COMMIT_RESERVE, [Sp68]::PAGE_RWX)
if ($mem -eq [IntPtr]::Zero) { $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: VirtualAllocEx err=$e"; Finish "FAIL alloc=$e" 1 }
$done = [IntPtr]::Zero
if (-not [Sp68]::WriteProcessMemory($hp, $mem, $bytes, [IntPtr] $bytes.Length, [ref] $done)) {
    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: WriteProcessMemory err=$e"; Finish "FAIL write=$e" 1
}
$rb = New-Object byte[] $bytes.Length
$null = [Sp68]::ReadProcessMemory($hp, $mem, $rb, [IntPtr] $rb.Length, [ref] $done)
$ok = (($rb -join ',') -eq ($bytes -join ','))
W ("path     : at 0x{0:X} ({1} B) readback={2}" -f $mem.ToInt64(), $bytes.Length, $(if ($ok) { 'match' } else { 'MISMATCH' }))
if (-not $ok) { Finish 'FAIL path-readback-mismatch' 1 }

# ---- remote LoadLibraryW --------------------------------------------------
$tid = 0
$ht = [Sp68]::CreateRemoteThread($hp, [IntPtr]::Zero, [IntPtr]::Zero, $remoteLL, $mem, 0, [ref] $tid)
if ($ht -eq [IntPtr]::Zero) { $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: CreateRemoteThread err=$e"; Finish "FAIL thread=$e" 1 }
W "thread   : CreateRemoteThread tid=$tid ht=$ht"
$wait = [Sp68]::WaitForSingleObject($ht, 8000)
$hmod = [IntPtr]::Zero
[void][Sp68]::GetExitCodeThread($ht, [ref] $hmod)
W ("wait     : 0x{0:X} (0=signalled) module=0x{1:X} (259=still active, 0=LoadLibrary failed)" -f $wait, $hmod.ToInt64())

# ---- read-back verdict (R3) -----------------------------------------------
$base = 0
for ($w = 0; $w -lt 12; $w++) {
    $base = [Sp68]::ModuleBase($procId, $dllName)
    if ($base -ne 0) { break }
    Start-Sleep -Milliseconds 250
}
if ($base -ne 0) { W ("module   : base=0x{0:X} -> LOADED" -f $base) } else { W 'module   : base=0 -> NOT loaded' }


if ($Eject -and $base -ne 0) {
    $t2 = 0
    $he = [Sp68]::CreateRemoteThread($hp, [IntPtr]::Zero, [IntPtr]::Zero, $remoteFL, [IntPtr] $base, 0, [ref] $t2)
    [void][Sp68]::WaitForSingleObject($he, 4000)
    W ("eject    : FreeLibrary thread=$he -> base now 0x{0:X}" -f ([Sp68]::ModuleBase($procId, $dllName)))
}

# ---- is the game still alive with the module in it? ----------------------
$diedAt = -1
for ($s = 0; $s -lt $HoldSec; $s++) {
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { $diedAt = $s; break }
}
$alive = ($diedAt -lt 0)
$fresh = (Test-Path -LiteralPath $logPath) -and ((Get-Item -LiteralPath $logPath).LastWriteTime -gt $t.StartTime)
$tail = if ($alive) { " (watched ${HoldSec} s)" } else { " (died ${diedAt} s after the load)" }
W ("after    : alive={0} moduleBase=0x{1:X} payloadLog={2}{3}" -f $alive, ([Sp68]::ModuleBase($procId, $dllName)), $fresh, $tail)
[void][Sp68]::VirtualFreeEx($hp, $mem, [IntPtr]::Zero, [Sp68]::MEM_RELEASE)
[void][Sp68]::CloseHandle($hp)
if (-not $alive) { Finish 'FAIL game-died-after-load' 1 }
if ($base -eq 0) { Finish 'FAIL module-not-loaded' 1 }
Finish 'PASS live-attach module loaded, game alive' 0

$fl = [Sp68]::GetProcAddress($k32, 'FreeLibrary')
$remoteK32 = [Sp68]::ModuleBase($procId, 'kernel32.dll')
if ($ll -eq [IntPtr]::Zero -or $remoteK32 -eq 0) { Finish 'FAIL cannot resolve LoadLibraryW' 1 }
$remoteLL = [IntPtr]($remoteK32 + ($ll.ToInt64() - $k32.ToInt64()))
$remoteFL = [IntPtr]($remoteK32 + ($fl.ToInt64() - $k32.ToInt64()))
W "remote   : kernel32=0x$($remoteK32.ToString('X')) LoadLibraryW=0x$($remoteLL.ToString('X'))"
