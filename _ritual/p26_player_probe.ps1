# p26_player_probe.ps1 -- AGENT B. Get APEX PLAYER DATA from user mode (no driver, no injection).
# Finds r5apex_dx12.exe / r5apex.exe (EA renames it - "baeleys game.exe"), opens it,
# resolves the game image base, then SCORES candidate entity-list / local-player RVAs
# and dumps live player rows (origin / health / team).
# run: powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p26_player_probe.ps1 [-Launch] [-WaitSec 180]
# writes: _ritual\p26_player.txt
param([switch]$Launch, [int]$WaitSec = 180)
$out = Join-Path $PSScriptRoot 'p26_player.txt'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
function W([string]$s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }

function H32($v) { '0x{0:X8}' -f ([int64]$v -band 0xFFFFFFFF) }

Add-Type @'
using System; using System.Runtime.InteropServices;
public static class R26 {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(int a, bool inh, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h, IntPtr b, byte[] buf, IntPtr n, out IntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  [DllImport("ntdll.dll")] public static extern int NtQueryInformationProcess(IntPtr h, uint cls, byte[] pbi, uint len, out uint ret);
  [DllImport("ntdll.dll")] public static extern int NtReadVirtualMemory(IntPtr h, IntPtr b, byte[] buf, IntPtr n, out IntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct MODULEENTRY32W { public uint dwSize; public uint th32ModuleID; public uint th32ProcessID;
    public uint GlblcntUsage; public uint ProccntUsage; public IntPtr modBaseAddr; public uint modBaseSize;
    public IntPtr hModule; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string szModule;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szExePath; }
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool Module32FirstW(IntPtr h, ref MODULEENTRY32W e);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool Module32NextW(IntPtr h, ref MODULEENTRY32W e);
}
'@
$RX = [regex]'^(r5apex|baeleys)'

W ("=== p26_player_probe  " + (Get-Date) + " ===")

function Find-Game {
    $pr = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'r5apex|baeleys' } | Select-Object -First 1
    if ($pr) { return $pr }
    if (-not $Launch) { return $null }
    $exe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $null }
    W ("launching " + $exe)
    Start-Process -FilePath $exe | Out-Null
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $WaitSec) {
        Start-Sleep -Seconds 3
        $pr = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'r5apex|baeleys' } | Select-Object -First 1
        if ($pr) { W ("game up after " + [int]((Get-Date) - $t0).TotalSeconds + "s pid=" + $pr.Id); return $pr }
    }
    return $null
}

$p = Find-Game
if (-not $p) { W "GAME NOT RUNNING (start Apex, then rerun with -Launch)"; W "=== DONE (no data) ==="; exit 1 }
W ("pid=" + $p.Id + " name=" + $p.ProcessName + " mb=" + [int]($p.WorkingSet64 / 1MB))

function Get-Base([int]$pidv, $proc) {
    try {
        $b = [uint64]$proc.MainModule.BaseAddress
        if ($b -gt 0x10000) { W ("  main module = " + $proc.MainModule.ModuleName + " base=0x" + $b.ToString('X') + " size=" + $proc.MainModule.ModuleMemorySize + " (via MainModule)"); return $b }
    } catch { W ("  MainModule failed: " + $_.Exception.Message) }
    $snap = [R26]::CreateToolhelp32Snapshot(0x18, [uint32]$pidv)
    if ($snap -eq [IntPtr](-1)) { W ("  Toolhelp32 snapshot failed err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); return 0 }
    $me = [R26+MODULEENTRY32W]::new()
    $me.dwSize = [Runtime.InteropServices.Marshal]::SizeOf([type][R26+MODULEENTRY32W])
    $found = 0; $n = 0
    if ([R26]::Module32FirstW($snap, [ref]$me)) {
        do {
            $n++
            if ($n -le 30) { W ("    mod " + $me.szModule + " base=0x" + ([uint64]$me.modBaseAddr).ToString('X') + " size=" + $me.modBaseSize) }
            if ($found -eq 0 -and ($me.szModule -match $RX -or $me.modBaseSize -gt 20000000)) { $found = [uint64]$me.modBaseAddr; W ("  matched module " + $me.szModule) }
        } while ([R26]::Module32NextW($snap, [ref]$me))
    } else { W ("  Module32FirstW failed err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
    [void][R26]::CloseHandle($snap)
    W ("  modules enumerated=" + $n)
    return $found
}
# --- open the process: EAC strips handle rights, so sweep every useful mask and
# --- keep the first handle whose PEB is actually readable ---
$peb = 0; $h = [IntPtr]::Zero; $readMask = 0
foreach ($m in @(0x410, 0x1010, 0x10, 0x400, 0x1000, 0x1008, 0x1020, 0x1F0FFF)) {
    $t = [R26]::OpenProcess($m, $false, $p.Id)
    if ($t -eq [IntPtr]::Zero) { W ("OpenProcess(0x" + $m.ToString('X') + ") DENIED err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); continue }
    $pbi = New-Object byte[] 0x30; $rr = 0
    $st = [R26]::NtQueryInformationProcess($t, 0, $pbi, 0x30, [ref]$rr)
    $pb = if ($st -eq 0) { [BitConverter]::ToUInt64($pbi, 8) } else { 0 }
    $buf = New-Object byte[] 8; $r2 = [IntPtr]::Zero; $rst = -1
    if ($pb -gt 0x10000) { $rst = [R26]::NtReadVirtualMemory($t, [IntPtr][int64]($pb + 0x10), $buf, [IntPtr]8, [ref]$r2) }
    W ("OpenProcess(0x" + $m.ToString('X') + ") handle=" + $t + " peb=0x" + $pb.ToString('X') + " NtReadVM=" + (H32 $rst) + " imageBase=0x" + [BitConverter]::ToUInt64($buf, 0).ToString('X'))
    if ($rst -eq 0 -and [BitConverter]::ToUInt64($buf, 0) -gt 0x10000) { $h = $t; $peb = $pb; $readMask = $m; break }
    if ($h -eq [IntPtr]::Zero) { $h = $t; $peb = $pb } else { [void][R26]::CloseHandle($t) }
}
if ($h -eq [IntPtr]::Zero) { W "OpenProcess failed for every mask"; W "=== DONE ==="; exit 3 }
W ("chosen handle mask=0x" + $readMask.ToString('X') + " peb=0x" + $peb.ToString('X'))

function MRD([uint64]$a, [int]$n) {
    $b = New-Object byte[] $n; $r = [IntPtr]::Zero
    if ([R26]::ReadProcessMemory($h, [IntPtr][int64]$a, $b, [IntPtr]$n, [ref]$r)) { $script:api = 'ReadProcessMemory'; return $b }
    $st = [R26]::NtReadVirtualMemory($h, [IntPtr][int64]$a, $b, [IntPtr]$n, [ref]$r)
    if ($st -eq 0) { $script:api = 'NtReadVirtualMemory'; return $b }
    $script:api = 'BLOCKED(st=0x' + $st.ToString('X8') + ')'; return $null
}
function RU64([uint64]$a) { $b = MRD $a 8; if ($b) { return [BitConverter]::ToUInt64($b, 0) } else { return 0 } }
function RF([uint64]$a) { $b = MRD $a 4; if ($b) { return [BitConverter]::ToSingle($b, 0) } else { return [single]::NaN } }
function RI([uint64]$a) { $b = MRD $a 4; if ($b) { return [BitConverter]::ToInt32($b, 0) } else { return -999 } }

# --- resolve the game image base: PEB first (never needs module enumeration) ---
$base = 0
$pbi = New-Object byte[] 0x30; $rr = 0
$st = [R26]::NtQueryInformationProcess($h, 0, $pbi, 0x30, [ref]$rr)
$peb = if ($st -eq 0) { [BitConverter]::ToUInt64($pbi, 8) } else { 0 }
W ("NtQueryInformationProcess(ProcessBasicInformation) st=0x" + $st.ToString('X8') + " peb=0x" + $peb.ToString('X'))
if ($peb -gt 0x10000) { $base = RU64 ($peb + 0x10); W ("PEB.ImageBaseAddress (read via " + $script:api + ") = 0x" + $base.ToString('X')) }
if ($base -le 0x10000) {
    try { $base = [uint64]$p.MainModule.BaseAddress; W ("base via MainModule = 0x" + $base.ToString('X')) } catch { W ("MainModule denied: " + $_.Exception.Message.Split([char]10)[0]) }
}
if ($base -le 0x10000) { $base = Get-Base $p.Id $p }
if ($base -le 0x10000) { W "game base NOT FOUND (PEB + MainModule + Toolhelp all failed)"; W "=== DONE ==="; exit 2 }

$mz = MRD $base 16
W ("RPM path in use: " + $script:api)
W ("MZ smoke test: " + $(if ($mz) { (($mz[0..1] | ForEach-Object { [char]$_ }) -join '') + ' : ' + (($mz | ForEach-Object { $_.ToString('X2') }) -join ' ') } else { 'UNREADABLE -> EAC blocks usermode RPM' }))
# --- candidate RVAs: documented (memory.h) first, then RE candidates from temp\globals.py ---
$EL = @(0x23F6A90, 0x0335D680, 0x03013C80, 0x02FCA848, 0x09B9A720)
$LP = @(0x01E7D4B8, 0x03E779D0)
$OFF_ORIGIN = 0x258; $OFF_TEAM = 0x478; $OFF_HEALTH = 0x3A0

if (-not $mz) { W "`nNOTE: ReadProcessMemory returned nothing -> EAC blocks user mode (driver/probe path needed)" }

W "`n--- scanning " + $EL.Count + " entityList x " + $LP.Count + " localPlayer candidates ---"
$rows = @()
foreach ($el in $EL) {
    $elv = RU64 ($base + $el)
    if ($elv -lt 0x10000) { W ("entityList@" + $el.ToString('X6') + " -> 0x" + $elv.ToString('X') + " (dead)"); continue }
    foreach ($lp in $LP) {
        $lpv = RU64 ($base + $lp)
        $hits = 0; $hp = 0; $samples = @()
        for ($i = 0; $i -lt 128; $i++) {
            $e = RU64 ($elv + $i * 8)
            if ($e -lt 0x10000) { continue }
            $x = RF ($e + $OFF_ORIGIN); $y = RF ($e + $OFF_ORIGIN + 4); $z = RF ($e + $OFF_ORIGIN + 8)
            if ([single]::IsNaN($x) -or [Math]::Abs($x) -gt 1e6 -or [single]::IsNaN($z) -or [Math]::Abs($z) -gt 1e6) { continue }
            $hits++
            $hpv = RI ($e + $OFF_HEALTH)
            if ($hpv -gt 0 -and $hpv -le 200) { $hp++ }
            if ($samples.Count -lt 2) { $samples += ("i=" + $i + " e=0x" + $e.ToString('X') + " o=(" + [Math]::Round($x, 1) + "," + [Math]::Round($y, 1) + "," + [Math]::Round($z, 1) + ") hp=" + $hpv) }
        }
        $rows += [pscustomobject]@{ EL = ('0x{0:X}' -f $el); LP = ('0x{0:X}' -f $lp); LocalPtr = ('0x{0:X}' -f $lpv); Valid = $hits; HealthOK = $hp }
    }
}
$rows | Format-Table -AutoSize | Out-String | ForEach-Object { W $_ }
foreach ($r in ($rows | Sort-Object -Descending Valid, HealthOK | Select-Object -First 2)) {
    W ("candidate " + $r.EL + " / " + $r.LP + " -> valid=" + $r.Valid + " healthOK=" + $r.HealthOK + " localPtr=" + $r.LocalPtr)
}

$best = $rows | Sort-Object -Descending Valid, HealthOK | Select-Object -First 1
if ($best -and $best.Valid -gt 0) {
    $elv = RU64 ($base + [Convert]::ToUInt32($best.EL, 16))
    $lpv = RU64 ($base + [Convert]::ToUInt32($best.LP, 16))
    $lt = RI ($lpv + $OFF_TEAM)
    W ("BEST entityList=" + $best.EL + " localPlayer=" + $best.LP + " localTeam=" + $lt)
    W "`n--- player rows ---"
    $n = 0
    for ($i = 0; $i -lt 128 -and $n -lt 24; $i++) {
        $e = RU64 ($elv + $i * 8); if ($e -lt 0x10000) { continue }
        $x = RF ($e + $OFF_ORIGIN); $y = RF ($e + $OFF_ORIGIN + 4); $z = RF ($e + $OFF_ORIGIN + 8)
        if ([single]::IsNaN($x)) { continue }
        $hpv = RI ($e + $OFF_HEALTH); $team = RI ($e + $OFF_TEAM); $n++
        W ("  #" + $n + " 0x" + $e.ToString('X') + "  (" + [Math]::Round($x, 1) + ", " + [Math]::Round($y, 1) + ", " + [Math]::Round($z, 1) + ")  hp=" + $hpv + "  team=" + $team + $(if ($team -eq $lt) { '  <ALLY/LOCAL>' } else { '  <ENEMY>' }))
    }
    W "`n>>> PLAYER DATA OBTAINED (user mode OpenProcess+ReadProcessMemory, no driver, no injection) <<<"
} else { W "no candidate produced plausible entities -> offsets need re-RE (see temp\globals.py)" }
[void][R26]::CloseHandle($h)
W "`n=== DONE -> _ritual\p26_player.txt ==="

