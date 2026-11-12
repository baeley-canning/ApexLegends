# s2_load_v14.ps1 -- session 2: load the staged v14 driver (run s2_stage_v14.ps1 first; hash-pinned
# to the 19:07 build). Same recipe the h318/h320/h321 chain used and the h329 VM bench co-validates:
# DSE 0 only for the length of the start, straight back to the boot byte 0x16 (R4), driver left
# RUNNING so the game gate sees driver-resident+DSE-on. R3 gates all three read-backs: sc RUNNING,
# DSE 0x16, IOCTL_VERSION 14 from the device. Self-elevating.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 's2_load_v14.out'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$d   = 'C:\Users\Public\p37'
$sys = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$V14 = '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
function Kdu([string[]]$a, [int]$cap = 25000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $d 'kdu.exe'; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit($cap)) { try { $p.Kill() } catch { } }
          Start-Sleep -Milliseconds 150
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
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
$IO_VER = [uint32](0x8A702004L)
function Ver { 
    $h = [Dev]::CreateFileW('\\.\ApexDrv', [uint32](0xC0000000L), 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) { return -1 }
    try { $v = New-Object byte[] 8; [uint32]$r = 0
          if (-not [Dev]::DeviceIoControl($h, $IO_VER, $v, 8, $v, 8, [ref]$r, [IntPtr]::Zero)) { return -2 }
          return [int][BitConverter]::ToUInt32($v, 0) } finally { [void][Dev]::CloseHandle($h) }
}
Lg '===== s2_load_v14 (v14 reload, leaves RUNNING) ====='
Lg ('game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' svc=[' + (SvcQ) + '] drv sha=' + (Get-FileHash $sys -Algorithm SHA256).Hash.Substring(0, 16))
if ((Get-FileHash $sys -Algorithm SHA256).Hash -ne $V14) { Lg 'RESULT: FAIL - staged image is not the v14 build (run s2_stage_v14.ps1)'; Emit; exit 1 }
$q = SvcQ
if ($q -match 'RUNNING') {
    $v = Ver
    if ($v -eq 14) { Lg ('RESULT: PASS - v14 already RUNNING (version 14 read-back); game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' untouched'); Emit; exit 0 }
    Lg ('svc RUNNING but version=' + $v + ' -> reload'); & "$env:SystemRoot\system32\sc.exe" stop apexdrv 2>&1 | Out-Null
    for ($i = 0; $i -lt 10 -and (SvcQ) -match 'RUNNING'; $i++) { Start-Sleep -Milliseconds 500 }
}
$o = Kdu @('-prv', '20', '-dse'); $pre = if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('dse_pre=0x' + $(if ($pre) { $pre } else { 'UNREADABLE' }))
if ($pre -notmatch '^0*0$') { Lg ('dse->0 out=[' + (Kdu @('-prv', '20', '-dse', '0')) + ']'); Start-Sleep -Milliseconds 400 }
& "$env:SystemRoot\system32\sc.exe" delete apexdrv 2>&1 | Out-Null
for ($i = 0; $i -lt 10 -and (SvcQ) -notmatch 'does not exist'; $i++) { Start-Sleep -Milliseconds 400 }
& "$env:SystemRoot\system32\sc.exe" create apexdrv type= kernel start= demand binPath= $sys 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" start apexdrv 2>&1 | Out-Null
Start-Sleep -Seconds 2
$q2 = SvcQ
Lg ('svc after start: ' + $q2)
if ($q2 -notmatch 'RUNNING') {
    if ($pre -and $pre -notmatch '^0*0$') { Lg ('start failed -> dse restore to 0x' + $pre + ' out=[' + (Kdu @('-prv', '20', '-dse', $pre)) + ']') } else { Lg ('start failed -> dse restore to 22 out=[' + (Kdu @('-prv', '20', '-dse', '22')) + ']') }
    Lg 'RESULT: FAIL - v14 did not start'; Emit; exit 1
}
Lg ('dse->22 out=[' + (Kdu @('-prv', '20', '-dse', '22')) + ']')
Start-Sleep -Milliseconds 400
$c2 = Kdu @('-prv', '20', '-dse', '22'); $six = if ($c2 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('dse final=0x' + $(if ($six) { $six } else { 'UNREADABLE' }))
$v = Ver
Lg ('device version read-back: ' + $v)
if ($six -match '^0*16$' -and $v -eq 14) { Lg ('RESULT: PASS - v14 RUNNING (version 14 read-back), dse 0x16 restored; game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' - next: h328'); Emit; exit 0 }
Lg 'RESULT: FAIL - dse or version read-back off'; Emit; exit 1
