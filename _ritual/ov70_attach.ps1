# ============================================================================
# _ritual\ov70_attach.ps1 - menu on screen, allocation-FREE variant.
#
# Variable vs ov69 (which got `PAGE_READWRITE err=5`, `PAGE_EXECUTE_READWRITE
# err=87`): the allocation itself.  The EAAC jail on this build refuses
# VirtualAllocEx in the target for every protection (ov59_alloc_probe had already
# seen err=5 for RW), so ov70 allocates NOTHING: it finds an existing committed
# RW page inside the game with VirtualQueryEx, writes the DLL path there, reads it
# back, and points a remote LoadLibraryW at it.  The string is the only thing
# that has to live in the target; the code that runs is kernel32!LoadLibraryW.
#
# Reversibility: the original bytes of the scratch page are saved and written
# back after the remote thread signals (the scraper only borrows the page).
# ============================================================================
param([int] $Pid0 = 0,
      [string] $Dll = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat.dll',
      [int] $WaitLogSec = 90,
      [switch] $Elevate, [switch] $Dump)

$ErrorActionPreference = 'Stop'
$rit  = $PSScriptRoot
$out  = Join-Path $rit 'ov70_attach.out'
$utf8 = [Text.UTF8Encoding]::new($false)
function W([string] $s) { [IO.File]::AppendAllText($out, $s + "`r`n", $utf8); Write-Host $s }
function Finish([string] $verdict, [int] $code) { W ''; W "RESULT: $verdict"; W "ov70 DONE $verdict"; exit $code }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }
    $arg = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevate -Pid0 {1} -Dll "{2}"' -f $PSCommandPath, $Pid0, $Dll)
    if ($Dump) { $arg += ' -Dump' }
    Start-Process powershell -Verb RunAs -ArgumentList $arg
    Write-Host 'ov70: relaunched elevated (UAC) - watch ov70_attach.out'
    exit 0
}
[IO.File]::WriteAllText($out, ("ov70 - allocation-free attach - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"), $utf8)
W ("elevated : $isAdmin")

# an elevated worker's console closes with it, so a terminating error must land
# in the output file - otherwise the run "just stops" (ov70 run 1, 15:46:43).
trap {
    W ("EXCEPTION: " + $_.Exception.GetType().Name + ': ' + $_.Exception.Message)
    W ("AT       : " + $_.InvocationInfo.PositionMessage)
    W 'ov70 DONE FAIL exception'
    break
}

$proc = if ($Pid0 -gt 0) { Get-Process -Id $Pid0 -ErrorAction SilentlyContinue } else { $null }
if (-not $proc) { $proc = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
if (-not $proc) { Finish 'FAIL no-game' 1 }
$procId  = [int] $proc.Id
$dllName = Split-Path -Leaf $Dll
W ("target   : pid=$procId title='$($proc.MainWindowTitle)'")

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sp70 {
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr OpenProcess(uint acc, bool inh, int pid);
    [DllImport("kernel32", SetLastError = true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr CreateRemoteThread(IntPtr hp, IntPtr sa, IntPtr stack, IntPtr start, IntPtr param, uint flags, out int tid);
    [DllImport("kernel32", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError = true)] public static extern bool GetExitCodeThread(IntPtr h, out IntPtr code);
    [DllImport("kernel32", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)] public static extern IntPtr GetProcAddress(IntPtr mod, string name);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr VirtualQueryEx(IntPtr hp, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential, Size = 48)]
    public struct MBI {
        public IntPtr BaseAddress; public IntPtr AllocationBase; public uint AllocationProtect;
        public ushort PartitionId; public ushort pad0; public ulong RegionSize;
        public uint State; public uint Protect; public uint Type; public uint pad1;
    }
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
        IntPtr snap = CreateToolhelp32Snapshot(0x08, (uint) pid);
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
    // first committed RW page (no execute) inside [start, start+span) with room
    public static ulong FindRwPage(IntPtr hp, ulong start, ulong span, ulong need) {
        ulong a = start & ~0xFFFUL;
        ulong end = start + span;
        while (a < end) {
            MBI m;
            if (VirtualQueryEx(hp, new IntPtr((long) a), out m, new IntPtr(Marshal.SizeOf(typeof(MBI)))) == IntPtr.Zero)
                a += 0x1000;
            else {
                ulong regionBase = (ulong) m.BaseAddress.ToInt64();
                ulong regionSize = m.RegionSize;
                uint prot = m.Protect;
                bool rw = (m.State == 0x1000) && ((prot & 0x04) != 0) && ((prot & 0x40) == 0) && ((prot & 0x100) == 0);
                if (rw && regionSize >= need) return regionBase + 0x800;
                a = regionBase + (regionSize > 0 ? regionSize : 0x1000);
            }
        }
        return 0;
    }
    public static string Census(IntPtr hp, ulong start, ulong span, ulong need) {
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        ulong a = start & ~0xFFFUL; ulong end = start + span;
        byte[] probe = new byte[need]; int rw = 0;
        while (a < end) {
            MBI m;
            IntPtr q = VirtualQueryEx(hp, new IntPtr((long) a), out m, new IntPtr(Marshal.SizeOf(typeof(MBI))));
            if (q == IntPtr.Zero) { a += 0x1000; continue; }
            ulong rb = (ulong) m.BaseAddress.ToInt64(); ulong rs = m.RegionSize; uint p = m.Protect;
            bool isrw = (m.State == 0x1000) && ((p & 0x04) != 0) && ((p & 0x40) == 0);
            if (isrw && rs >= need) {
                rw++;
                if (rw <= 25) {
                    ulong cand = rb + rs - need; IntPtr got;
                    bool ok = ReadProcessMemory(hp, new IntPtr((long) cand), probe, new IntPtr(probe.Length), out got);
                    int nz = 0; if (ok) for (int i = 0; i < probe.Length; i++) if (probe[i] != 0) nz++;
                    sb.AppendLine(string.Format("rw#{0} base=0x{1:X} size=0x{2:X} prot=0x{3:X} tailRead={4} nonzeroBytes={5}",
                                                rw, rb, rs, p, ok, nz));
                }
            }
            a = rb + (rs > 0 ? rs : 0x1000);
        }
        sb.AppendLine("rw regions total = " + rw);
        return sb.ToString();
    }
    public static int Scanned = 0;
    public static int QueryFail = 0;
    public static uint LastError = 0;
    // first committed RW page (no execute) inside [start, start+span) whose TAIL
    // (exactly `need` bytes) reads back all-zero - i.e. section/heap padding that
    // nothing is using. The zero test is the read-back that makes the borrow safe.
    public static ulong FindZeroRwPage(IntPtr hp, ulong start, ulong span, ulong need) {
        ulong a = start & ~0xFFFUL;
        ulong end = start + span;
        byte[] probe = new byte[need];
        while (a < end) {
            Scanned++;
            MBI m;
            IntPtr q = VirtualQueryEx(hp, new IntPtr((long) a), out m, new IntPtr(Marshal.SizeOf(typeof(MBI))));
            if (q == IntPtr.Zero) { QueryFail++; LastError = (uint) Marshal.GetLastWin32Error(); a += 0x1000; continue; }
            ulong rb = (ulong) m.BaseAddress.ToInt64();
            ulong rs = m.RegionSize;
            uint p = m.Protect;
            bool rw = (m.State == 0x1000) && ((p & 0x04) != 0) && ((p & 0x40) == 0) && ((p & 0x100) == 0);
            if (rw && rs >= need) {
                ulong cand = rb + rs - need;
                IntPtr got;
                if (ReadProcessMemory(hp, new IntPtr((long) cand), probe, new IntPtr(probe.Length), out got)) {
                    bool zero = true;
                    for (int i = 0; i < probe.Length; i++) { if (probe[i] != 0) { zero = false; break; } }
                    if (zero) return cand;
                }
            }
            a = rb + (rs > 0 ? rs : 0x1000);
        }
        return 0;
    }
}
'@


$PROC_ALL = 0x1F0FFF
$hp = [Sp70]::OpenProcess($PROC_ALL, $false, $procId)
if ($hp -eq [IntPtr]::Zero) { $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: OpenProcess err=$e"; Finish "FAIL openprocess=$e" 1 }
W "handle   : OpenProcess(ALL) ok hproc=$hp"

# ---- where the string can live (no allocation) -------------------------------
$exeBase = [Sp70]::Base($procId, 'r5apex_dx12.exe')
if ($exeBase -eq 0) { $exeBase = [Sp70]::Base($procId, 'r5apex.exe') }
W (("image    : r5apex base=0x{0:X}" -f $exeBase))
$bytes = [Text.Encoding]::Unicode.GetBytes($Dll + "`0")
$need  = [uint64]($bytes.Length + 64)

$scratch = 0
[Sp70]::Scanned = 0; [Sp70]::QueryFail = 0
if ($exeBase -ne 0) { $scratch = [Sp70]::FindZeroRwPage($hp, $exeBase, 0x40000000, $need) }
if ($scratch -eq 0) { $scratch = [Sp70]::FindZeroRwPage($hp, 0x10000, 0x7FFE0000, $need) }
W ("scan     : regions={0} queryFail={1} lastErr={2} mbiSize={3}" -f `
    [Sp70]::Scanned, [Sp70]::QueryFail, [Sp70]::LastError, [Runtime.InteropServices.Marshal]::SizeOf([type]'Sp70+MBI'))
if ($Dump) {
    $census = [Sp70]::Census($hp, 0x10000, 0x7FFE0000, $need)
    W '---- census ----'
    W $census
    Finish 'CENSUS (dump mode, nothing written)' 0
}
if ($scratch -eq 0) { W 'FAIL: no committed RW page found in target'; Finish 'FAIL no-rw-page' 1 }
$addr = [IntPtr][int64] $scratch
W (("scratch  : 0x{0:X} ({1} B needed)" -f $scratch, $bytes.Length))

$orig = New-Object byte[] $bytes.Length
$done = [IntPtr]::Zero
if (-not [Sp70]::ReadProcessMemory($hp, $addr, $orig, [IntPtr] $orig.Length, [ref] $done)) {
    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: ReadProcessMemory err=$e"; Finish "FAIL pre-read=$e" 1
}
if (-not [Sp70]::WriteProcessMemory($hp, $addr, $bytes, [IntPtr] $bytes.Length, [ref] $done)) {
    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: WriteProcessMemory err=$e"; Finish "FAIL write=$e" 1
}
$rb = New-Object byte[] $bytes.Length
$null = [Sp70]::ReadProcessMemory($hp, $addr, $rb, [IntPtr] $rb.Length, [ref] $done)
$okPath = (($rb -join ',') -eq ($bytes -join ','))
W ("path     : written, readback=$(if ($okPath) { 'match' } else { 'MISMATCH' })")
if (-not $okPath) { Finish 'FAIL path-readback-mismatch' 1 }

# ---- remote LoadLibraryW ----------------------------------------------------
$localK32  = [Sp70]::GetModuleHandleW('kernel32.dll')
$localLL   = [Sp70]::GetProcAddress($localK32, 'LoadLibraryW')
$remoteK32 = [Sp70]::Base($procId, 'kernel32.dll')
if ($remoteK32 -eq 0) { Finish 'FAIL kernel32 base unreadable' 1 }
$remoteLL = [IntPtr]($remoteK32 + ($localLL.ToInt64() - $localK32.ToInt64()))
$tid = 0
$ht = [Sp70]::CreateRemoteThread($hp, [IntPtr]::Zero, [IntPtr]::Zero, $remoteLL, $addr, 0, [ref] $tid)
if ($ht -eq [IntPtr]::Zero) { $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); W "FAIL: CreateRemoteThread err=$e"; Finish "FAIL thread=$e" 1 }
$wait = [Sp70]::WaitForSingleObject($ht, 10000)
$hmod = [IntPtr]::Zero
[void][Sp70]::GetExitCodeThread($ht, [ref] $hmod)
W (("thread   : tid={0} wait=0x{1:X} hmod=0x{2:X}" -f $tid, $wait, $hmod.ToInt64()))

$base = 0
for ($i = 0; $i -lt 20; $i++) {
    $base = [Sp70]::Base($procId, $dllName)
    if ($base -ne 0) { break }
    Start-Sleep -Milliseconds 250
}
W (("module   : {0} base=0x{1:X}" -f $dllName, $base))
# give the scratch bytes back
[void][Sp70]::WriteProcessMemory($hp, $addr, $orig, [IntPtr] $orig.Length, [ref] $done)
W 'restore  : scratch page bytes written back'
if ($base -eq 0) {
    $alive0 = [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
    W "check    : game alive=$alive0"
    Finish ("FAIL module-not-loaded (wait=0x{0:X} hmod={1})" -f $wait, $hmod.ToInt64()) 1
}

W ("payload  : $Dll ($((Get-Item -LiteralPath $Dll).Length) B)")

# ---- 4: payload oracle (R3) -------------------------------------------------
$t0 = Get-Date
$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\payload_$procId.log"
W "log      : $logPath"
$fresh = $false
$deadline = (Get-Date).AddSeconds($WaitLogSec)
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $logPath) {
        if ((Get-Item -LiteralPath $logPath).LastWriteTime -gt $t0.AddSeconds(-2)) { $fresh = $true; break }
    }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
$readyHit = $false
if (-not $fresh) { W 'oracle   : no fresh payload log' }
else {
    $deadline2 = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline2) {
        if ([IO.File]::ReadAllText($logPath) -match 'overlay ready|Render hook installed') { $readyHit = $true; break }
        if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 700
    }
    W "oracle   : fresh=True ready=$readyHit"
}

# ---- 5: frames --------------------------------------------------------------
function Shot([string] $tag, [string] $key) {
    if ($key) {
        $k = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'h159_insertkey.ps1') `
              -Pid $procId -Out (Join-Path $rit "ov70_key_$tag.txt")) -join ' | '
        W "key      : $tag -> $k"
        Start-Sleep -Seconds 2
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'shot_desk.ps1') | Out-Null
    $shot = Join-Path $rit "ov70_shot_$tag.png"
    Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') -Destination $shot -Force
    W ("shot     : $shot ($((Get-Item -LiteralPath $shot).Length) B)")
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'ocr.ps1') `
        -Path $shot -Out (Join-Path $rit "ov70_ocr_$tag.txt") | Out-Null
    return (Join-Path $rit "ov70_ocr_$tag.txt")
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
if ($fresh) { Copy-Item -LiteralPath $logPath -Destination (Join-Path $rit "ov70_payload_$procId.log") -Force }
$pass = $aliveEnd -and $readyHit -and $menuHit
Finish $(if ($pass) { ("PASS menu{0} on screen (alive={1}, base=0x{2:X})" -f $espTag, $aliveEnd, $base) } else { 'FAIL see checks above' }) $(if ($pass) { 0 } else { 2 })

