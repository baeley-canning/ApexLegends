# h323_fire_ioctl.ps1 - h323: the transient kernel probe, driven straight from PowerShell.
# h322 proved \\.\ApexDrv answers IOCTL_VERSION 14 on a NON-elevated handle, so no SCM, no kdu,
# no DSE flip, no UAC and no schtasks are needed - the driver stays loaded and registered.
# Struct is APEXDRV_PROBE_REQUEST, pack(1), 84 bytes (32-byte PEB tail); offsets below come
# from apex_driver_ioctl.h.  Phase 0 dry-runs PID 4 (System, harmless) to prove the marshalling,
# then ONE real probe against the game, then a 60 s timed liveness watch.
param([switch]$DryOnly)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h323_fire_ioctl.out'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Dev {
  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFileW(string p, uint a, uint s, IntPtr sa, uint d, uint fl, IntPtr t);
  [DllImport("kernel32", SetLastError=true)]
  public static extern bool DeviceIoControl(IntPtr h, uint c, byte[] i, uint il, byte[] o, uint ol, out uint r, IntPtr ov);
  [DllImport("kernel32")] public static extern bool CloseHandle(IntPtr h);
}
'@
$IO_VER = [uint32](0x8A702004L); $IO_PROBE = [uint32](0x8A702008L)
function OpenDev {
    $h = [Dev]::CreateFileW('\\.\ApexDrv', [uint32](0xC0000000L), 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) { throw ('CreateFile \\.\ApexDrv failed err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
    return $h
}
function Probe([int]$procId, [string]$tag) {
    $h = OpenDev
    try {
        $v = New-Object byte[] 8; [uint32]$r = 0
        if (-not [Dev]::DeviceIoControl($h, $IO_VER, $v, 8, $v, 8, [ref]$r, [IntPtr]::Zero)) { Lg ($tag + ' VERSION ioctl failed err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); return $null }
        $ver = [BitConverter]::ToUInt32($v, 0); Lg ($tag + ' driver version ' + $ver)
        if ($ver -ne 14) { Lg ($tag + ' unexpected ABI ' + $ver); return $null }
        $req = New-Object byte[] 84
        [BitConverter]::GetBytes([int]$procId).CopyTo($req, 0)          # ProcessId @0, Flags @4 stays 0
        [uint32]$ret = 0
        $ok = [Dev]::DeviceIoControl($h, $IO_PROBE, $req, 84, $req, 84, [ref]$ret, [IntPtr]::Zero)
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Lg ($tag + ' PROBE rc=' + $ok + ' err=' + $err + ' info=' + $ret)
        if (-not $ok) { return $null }
        Lg ($tag + '   PsLookup        0x' + ([BitConverter]::ToInt32($req, 8)).ToString('X8'))
        Lg ($tag + '   ObOpen full     0x' + ([BitConverter]::ToInt32($req, 12)).ToString('X8'))
        Lg ($tag + '   ZwAllocate      0x' + ([BitConverter]::ToInt32($req, 16)).ToString('X8') + ' at 0x' + ([BitConverter]::ToUInt64($req, 44)).ToString('X'))
        Lg ($tag + '   Write(attach)   0x' + ([BitConverter]::ToInt32($req, 20)).ToString('X8'))
        Lg ($tag + '   ZwFree          0x' + ([BitConverter]::ToInt32($req, 24)).ToString('X8'))
        Lg ($tag + '   MmCopy peb      0x' + ([BitConverter]::ToInt32($req, 28)).ToString('X8') + ' copied=' + [BitConverter]::ToUInt32($req, 32) + ' peb=0x' + ([BitConverter]::ToUInt64($req, 36)).ToString('X'))
        $allOk = ([BitConverter]::ToInt32($req, 16) -eq 0) -and ([BitConverter]::ToInt32($req, 20) -eq 0) -and ([BitConverter]::ToInt32($req, 24) -eq 0)
        return $allOk
    } finally { [void][Dev]::CloseHandle($h) }
}
Lg '===== h323 raw-IOCTL transient probe (non-elevated) ====='
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=' + (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|1060' }) -join '').Trim())

try { $null = Probe 4 'dry(pid4)' } catch { Lg ('dry run FAILED: ' + $_.Exception.Message); Emit; exit 1 }
if ($DryOnly) { Lg 'DRY ONLY - marshalling validated, no fuse armed'; Emit; exit 0 }
Lg 'ARMED - launch the game now (15 min window)'
$sw = [Diagnostics.Stopwatch]::StartNew()
$tp = 0
while ($sw.Elapsed.TotalMinutes -lt 15 -and -not $tp) { Start-Sleep -Milliseconds 250; $g = @(Get-Process r5apex_dx12 -EA 0); if ($g.Count) { $tp = $g[0].Id } }
if (-not $tp) { Lg 'RESULT: NO-OP - no game in 15 min (driver left RUNNING)'; Emit; exit 3 }
$t0 = Get-Date
Lg ('pid=' + $tp + ' detected - holding 1000 ms')
Start-Sleep -Milliseconds 1000
$swp = [Diagnostics.Stopwatch]::StartNew()
$okp = $false
try { $okp = Probe $tp 'game' } catch { Lg ('game probe FAILED: ' + $_.Exception.Message) }
Lg ('probe returned at +' + [int]$swp.Elapsed.TotalMilliseconds + ' ms, transient_op_ok=' + $okp)
if ($okp -ne $true) { Lg 'ok=null/false -> no alloc+write happened, verdict below is not about the variable' }
$died = -1
for ($i = 1; $i -le 60; $i++) { Start-Sleep -Milliseconds 1000; if (-not (Get-Process -Id $tp -EA 0)) { $died = $i; break } }
if ($died -gt 0) { Lg ('VERDICT: DEAD +' + $died + ' s after the transient write (alloc+write+free, nothing left resident)') }
else { Lg 'VERDICT: ALIVE 60 s after the transient write - residency is NOT the variable; the kill is bound to what the map leaves resident (or to its entry call)' }
Emit
