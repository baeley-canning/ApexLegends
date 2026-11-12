# ============================================================================
# _ritual\ov69_attach.ps1 - put the MENU on screen in the live game (R5: new
# number, one variable).
#
# Variable vs ov68 (which died at `VirtualAllocEx err=87`): allocation
# PROTECTION, not target and not method.  ov68 asked for PAGE_EXECUTE_READWRITE
# (0x40); 87 = ERROR_INVALID_PARAMETER is what an ACG (arbitrary-code-guard)
# target answers when a *writable*+executable page is requested.  ov69 asks for
# PAGE_READWRITE (0x04) because the buffer holds nothing but the DLL path - the
# code that runs is kernel32!LoadLibraryW, already in the target.  Same
# OpenProcess(ALL) elevated handle, same CreateRemoteThread, same readback.
#
# Steps (each one is a read-back, R3):
#   1. resolve the live r5apex_dx12 pid (never create one - ov67/ov68)
#   2. alloc RW + write the path + read the path back
#   3. remote LoadLibraryW, then confirm apexcheat.dll in the target's module list
#   4. confirm %LOCALAPPDATA%\QwenKern\payload_<pid>.log is FRESH (this run)
#      and reaches 'overlay ready'
#   5. INSERT (menu), shot + OCR; INSERT (close), shot + OCR for the ESP frame
#
# Reversibility: nothing is freed and nothing is terminated - the module stays
# loaded until the game exits (that is the state the user asked for).  Re-run is
# safe: a second LoadLibraryW on a resident module just bumps the refcount.
# ============================================================================
param([int] $Pid0 = 0,
      [string] $Dll = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat.dll',
      [int] $WaitLogSec = 90,
      [switch] $Elevate)

$ErrorActionPreference = 'Stop'
$rit  = $PSScriptRoot
$out  = Join-Path $rit 'ov69_attach.out'
$utf8 = [Text.UTF8Encoding]::new($false)
function W([string] $s) { [IO.File]::AppendAllText($out, $s + "`r`n", $utf8); Write-Host $s }
function Finish([string] $verdict, [int] $code) { W ''; W "RESULT: $verdict"; W "ov69 DONE $verdict"; exit $code }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and $Elevate) {
    if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }
    $arg = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevate -Pid0 {1} -Dll "{2}"' -f
            $PSCommandPath, $Pid0, $Dll)
    Start-Process powershell -Verb RunAs -ArgumentList $arg
    Write-Host 'ov69: relaunched elevated (UAC) - watch ov69_attach.out'
    exit 0
}

[IO.File]::WriteAllText($out, ("ov69 - menu on screen in the live game - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"), $utf8)
W ("elevated : $isAdmin")

# ---- 1: the live target -----------------------------------------------------
$proc = if ($Pid0 -gt 0) { Get-Process -Id $Pid0 -ErrorAction SilentlyContinue } else { $null }
if (-not $proc) { $proc = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
if (-not $proc) { Finish 'FAIL no-game (launch Apex first: ov69_launch.ps1)' 1 }
$procId = [int] $proc.Id
$dllName = Split-Path -Leaf $Dll
W ("target   : pid=$procId title='$($proc.MainWindowTitle)' hwnd=$($proc.MainWindowHandle)")
W ("payload  : $Dll ($((Get-Item -LiteralPath $Dll).Length) B, $((Get-Item -LiteralPath $Dll).LastWriteTime))")


Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sp69 {
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr OpenProcess(uint acc, bool inh, int pid);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, IntPtr size, uint type, uint prot);
    [DllImport("kernel32", SetLastError = true)] public static extern bool VirtualFreeEx(IntPtr hp, IntPtr addr, IntPtr size, uint type);
    [DllImport("kernel32", SetLastError = true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr CreateRemoteThread(IntPtr hp, IntPtr sa, IntPtr stack, IntPtr start, IntPtr param, uint flags, out int tid);
    [DllImport("kernel32", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError = true)] public static extern bool GetExitCodeThread(IntPtr h, out IntPtr code);
    [DllImport("kernel32", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)] public static extern IntPtr GetProcAddress(IntPtr mod, string name);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct MODULEENTRY32 {
        public uint dwSize; public uint th32ModuleID; public uint th32ProcessID;
        public uint GlblcntUsage; public uint ProccntUsage; public IntPtr modBaseAddr;
        public uint modBaseSize; public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExePath;
    }
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)] static extern bool Module32First(IntPtr snap, ref MODULEENTRY32 me);
    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)] static extern bool Module32Next(IntPtr snap, ref MODULEENTRY32 me);
    public static ulong Base(int pid, string name) {
        IntPtr snap = CreateToolhelp32Snapshot(0x08, (uint) pid);   // TH32CS_SNAPMODULE
        if (snap == new IntPtr(-1)) return 0;
        try {
            MODULEENTRY32 me = new MODULEENTRY32();
            me.dwSize = (uint) Marshal.SizeOf(typeof(MODULEENTRY32));
            if (!Module32First(snap, ref me)) return 0;
            do {
                if (string.Equals(me.szModule, name, StringComparison.OrdinalIgnoreCase))
                    return (ulong) me.modBaseAddr.ToInt64();
            } while (Module32Next(snap, ref me));
            return 0;
        } finally { CloseHandle(snap); }
    }
}
'@

$MEM_COMMIT_RESERVE = 0x3000
$PAGE_READWRITE     = 0x04
$PAGE_RWX           = 0x40
$PROC_ALL           = 0x1F0FFF


# ---- 2: handles + path buffer -----------------------------------------------
$hp = [Sp69]::OpenProcess($PROC_ALL, $false, $procId)
if ($hp -eq [IntPtr]::Zero) { $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: OpenProcess err=$e"; Finish "FAIL openprocess=$e" 1 }
W "handle   : OpenProcess(ALL) ok hproc=$hp"

$t0 = Get-Date
$bytes = [Text.Encoding]::Unicode.GetBytes($Dll + "`0")
$mem = [Sp69]::VirtualAllocEx($hp, [IntPtr]::Zero, [IntPtr] $bytes.Length, $MEM_COMMIT_RESERVE, $PAGE_READWRITE)
$allocProt = 'rw'
if ($mem -eq [IntPtr]::Zero) {
    $e1 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    W "alloc    : PAGE_READWRITE err=$e1"
    $allocProt = 'rwx-fallback'
    $mem = [Sp69]::VirtualAllocEx($hp, [IntPtr]::Zero, [IntPtr] $bytes.Length, $MEM_COMMIT_RESERVE, $PAGE_RWX)
    if ($mem -eq [IntPtr]::Zero) {
        $e2 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W "alloc    : PAGE_EXECUTE_READWRITE err=$e2"
        Finish "FAIL alloc rw=$e1 rwx=$e2" 1
    }
}
W ("alloc    : 0x{0:X} ({1} B, {2})" -f $mem.ToInt64(), $bytes.Length, $allocProt)
$done = [IntPtr]::Zero
if (-not [Sp69]::WriteProcessMemory($hp, $mem, $bytes, [IntPtr] $bytes.Length, [ref] $done)) {
    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: WriteProcessMemory err=$e"; Finish "FAIL write=$e" 1
}
$rb = New-Object byte[] $bytes.Length
$null = [Sp69]::ReadProcessMemory($hp, $mem, $rb, [IntPtr] $rb.Length, [ref] $done)
$okPath = (($rb -join ',') -eq ($bytes -join ','))
W (("path     : at 0x{0:X} readback={1}" -f $mem.ToInt64(), $(if ($okPath) { 'match' } else { 'MISMATCH' })))
if (-not $okPath) { Finish 'FAIL path-readback-mismatch' 1 }

# ---- 3: remote LoadLibraryW -------------------------------------------------
$localK32 = [Sp69]::GetModuleHandleW('kernel32.dll')
$localLL  = [Sp69]::GetProcAddress($localK32, 'LoadLibraryW')
$remoteK32 = [Sp69]::Base($procId, 'kernel32.dll')
if ($remoteK32 -eq 0) { Finish 'FAIL target kernel32 base unreadable (module list denied)' 1 }
$remoteLL = [IntPtr]($remoteK32 + ($localLL.ToInt64() - $localK32.ToInt64()))
W (("remote   : kernel32=0x{0:X} LoadLibraryW=0x{1:X}" -f $remoteK32, $remoteLL.ToInt64()))

$tid = 0
$ht = [Sp69]::CreateRemoteThread($hp, [IntPtr]::Zero, [IntPtr]::Zero, $remoteLL, $mem, 0, [ref] $tid)
if ($ht -eq [IntPtr]::Zero) { $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: CreateRemoteThread err=$e"; Finish "FAIL thread=$e" 1 }
W "thread   : tid=$tid"
$wait = [Sp69]::WaitForSingleObject($ht, 10000)
$hmod = [IntPtr]::Zero
[void][Sp69]::GetExitCodeThread($ht, [ref] $hmod)
W (("wait     : 0x{0:X} (0=signalled) hmod=0x{1:X} (259=still running, 0=LoadLibrary failed)" -f $wait, $hmod.ToInt64()))

$base = 0
for ($i = 0; $i -lt 20; $i++) {
    $base = [Sp69]::Base($procId, $dllName)
    if ($base -ne 0) { break }
    Start-Sleep -Milliseconds 250
}
W (("module   : {0} base=0x{1:X}" -f $dllName, $base))
if ($base -eq 0) {
    $alive0 = [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
    W "check    : game alive=$alive0"
    Finish ("FAIL module-not-loaded (thread wait=0x{0:X} hmod={1})" -f $wait, $hmod.ToInt64()) 1

# ---- 4: the payload's own oracle log (R3: the log is the verdict) ----------
$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\payload_$procId.log"
W "log      : $logPath"
$fresh = $false
$deadline = (Get-Date).AddSeconds($WaitLogSec)
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $logPath) {
        if ((Get-Item -LiteralPath $logPath).LastWriteTime -gt $t0) { $fresh = $true; break }
    }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
$readyHit = $false
if (-not $fresh) { W 'oracle   : no fresh payload log (DllMain did not reach Application::Initialize)' }
else {
    $aliveMid = $true
    $deadline2 = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline2) {
        $txt = [IO.File]::ReadAllText($logPath)
        if ($txt -match 'overlay ready|Render hook installed') { $readyHit = $true; break }
        if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { $aliveMid = $false; break }
        Start-Sleep -Milliseconds 700
    }
    W "oracle   : fresh=True ready=$readyHit gameAlive=$aliveMid"
}

# ---- 5: menu + ESP frames ---------------------------------------------------
function Shot([string] $tag, [string] $key) {
    if ($key) {
        $k = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'h159_insertkey.ps1') `
              -Pid $procId -Out (Join-Path $rit "ov69_key_$tag.txt")) -join ' | '
        W "key      : $tag -> $k"
        Start-Sleep -Seconds 2
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'shot_desk.ps1') | Out-Null
    $shot = Join-Path $rit "ov69_shot_$tag.png"
    Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') -Destination $shot -Force
    W ("shot     : $shot ($((Get-Item -LiteralPath $shot).Length) B)")
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'ocr.ps1') `
        -Path $shot -Out (Join-Path $rit "ov69_ocr_$tag.txt") | Out-Null
    return (Join-Path $rit "ov69_ocr_$tag.txt")
}

$ocrMenu = Shot 'menu' 'INSERT'
$menuTxt = if (Test-Path $ocrMenu) { [IO.File]::ReadAllText($ocrMenu) } else { '' }
W '---- OCR (menu frame) ----'
W $menuTxt

$ocrEsp = Shot 'esp' 'INSERT'
$espTxt = if (Test-Path $ocrEsp) { [IO.File]::ReadAllText($ocrEsp) } else { '' }
W '---- OCR (esp frame) ----'
W $espTxt

# ---- 6: verdict -------------------------------------------------------------
$aliveEnd = [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
$logTxt   = if ($fresh) { [IO.File]::ReadAllText($logPath) } else { '' }
$menuHit  = ($menuTxt -match 'QWENKERN|AIMBOT|VISUALS|MISCELLANEOUS|EXPLOITS|SETTINGS|ESP')
$espHit   = ($espTxt  -match 'ESP|BOX|PLAYER|LOOT')
$espTag   = if ($espHit) { '+esp' } else { '' }
Write-Host ''
W ("check module loaded  : base=0x{0:X}" -f $base)
W "check payload log    : fresh=$fresh ready=$readyHit"
W "check menu on screen : $menuHit"
W "check esp text       : $espHit"
W "check game alive     : $aliveEnd"
if ($fresh) { Copy-Item -LiteralPath $logPath -Destination (Join-Path $rit "ov69_payload_$procId.log") -Force }
W "artifacts            : ov69_shot_menu.png, ov69_ocr_menu.txt, ov69_shot_esp.png, ov69_ocr_esp.txt, ov69_payload_$procId.log"

$pass = $aliveEnd -and $readyHit -and $menuHit
Finish $(if ($pass) { ("PASS menu{0} on screen (alive={1}, base=0x{2:X})" -f $espTag, $aliveEnd, $base) } else { 'FAIL see checks above' }) $(if ($pass) { 0 } else { 2 })

}
