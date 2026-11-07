# ============================================================================
# _ritual\qk_drv_up.ps1 - bring apexdrv v15 up for one session (and park DSE again).
#
# Why: v15 adds IOCTL_APEXDRV_DTB (KPROCESS.DirectoryTableBase, EPROCESS+0x28).
# That is the exact CR3 a zero-attach page walk needs, so discovery stops being a
# physical-memory hunt (which needed a per-build EPROCESS offset and rebooted the
# host once).  apexdrv is self-signed, so it needs a DSE window to load.
#
# Order, and the read-back is the verdict (R3):
#   1. stage build\apexdrv.sys -> System32\drivers\apexdrv.sys
#   2. read DSE (prv 20/16/17); if != 0 write 0 via prv 20 and read back
#   3. sc start ApexDrv ; sc query (STATE 4 = running)
#   4. restore DSE to the value read in (2); read back
#   5. run qk_va against explorer.exe to prove the driver path end to end
#
# Usage: powershell -ExecutionPolicy Bypass -File _ritual\qk_drv_up.ps1
# ============================================================================
[CmdletBinding()]
param([string] $OutFile = '')

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
if (-not $OutFile) { $OutFile = Join-Path $here 'qk_drv_up.out' }

$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) {
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"'), '-OutFile', ('"' + $OutFile + '"')) -Verb RunAs
    exit 0
}

$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $OutFile -Value ($L -join "`r`n") }

$kdu = 'C:\Users\Public\p37\kdu.exe'
function Kdu([string[]]$a) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $kdu; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = 'C:\Users\Public\p37'
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch { } }
        return ($t1.Result + $t2.Result)
    } catch { return $_.Exception.Message }
}
function DseRead {
    foreach ($id in 20, 16, 17, 0) {
        $r = Kdu @('-prv', "$id", '-dse')
        if ($r -match 'value:\s*([0-9A-Fa-f]+)') { return @($matches[1], $id) }
    }
    return @('', 0)
}

Lg '===== qk drv up (apexdrv v15 + one DSE window) ====='

$sys = Join-Path $env:WINDIR 'System32\drivers\apexdrv.sys'
$bld = Join-Path $root 'QwenKernPremium\build\apexdrv.sys'
if (-not (Test-Path -LiteralPath $bld)) { Lg "RESULT: FAIL - $bld missing"; Emit; exit 1 }
Lg ('build file: ' + (Get-Item $bld).Length + ' bytes, ' + (Get-Item $bld).LastWriteTime)

$pre, $prov = DseRead
if (-not $pre) { Lg 'RESULT: FAIL - DSE unreadable, no write performed'; Emit; exit 1 }
Lg ('pre DSE=0x' + $pre + ' (via prv ' + $prov + ')')

$restore = $pre
if ($pre -notmatch '^0+$') {
    $w = Kdu @('-prv', '20', '-dse', '0')
    Lg ('write DSE 0: ' + (($w -replace '\s+', ' ').Trim()))
    Start-Sleep -Milliseconds 500
    $chk, $p2 = DseRead
    Lg ('DSE after write=0x' + $(if ($chk) { $chk } else { 'UNREADABLE' }))
    if ($chk -notmatch '^0+$') { Lg 'RESULT: FAIL - DSE write did not take; driver not started'; Emit; exit 1 }
} else { Lg 'DSE already 0 - window already open' }

# A running service keeps its loaded image AND its file open: stop -> copy -> start.
# (Measured: copying before the stop failed silently and v15 stayed loaded while the
#  logs said "staged".)
$st = & sc.exe stop ApexDrv 2>&1 | Out-String
Lg ('sc stop: ' + (($st -replace '\s+', ' ').Trim()))
Start-Sleep -Seconds 1
Copy-Item -LiteralPath $bld -Destination $sys -Force -ErrorAction Continue
if (-not (Test-Path -LiteralPath $sys)) { Lg 'RESULT: FAIL - copy did not land'; Emit; exit 1 }
Lg ('staged -> ' + $sys + ' (' + (Get-Item $sys).Length + ' bytes, ' + (Get-Item $sys).LastWriteTime + ')')

$s = & sc.exe start ApexDrv 2>&1 | Out-String
Lg ('sc start: ' + (($s -replace '\s+', ' ').Trim()))
Start-Sleep -Milliseconds 700
$q = & sc.exe query ApexDrv 2>&1 | Out-String
$running = ($q -match 'STATE\s+:\s+4\s+RUNNING')
Lg ('driver running=' + $running)

# Read the ABI the driver actually reports - the only proof the new image loaded.
$verpy = Join-Path $here '..\temp\_ver.py'
$py2 = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
if (Test-Path -LiteralPath $verpy) {
    & $py2 $verpy | ForEach-Object { Lg ('  ver| ' + $_) }
}

if ($pre -ne '0') {
    # kdu parses -dse as DECIMAL: 0x16 must be passed as 22.  A bare -dse WRITES 0,
    # so the value is never read back with a bare call after the restore.
    $dec = [Convert]::ToInt32($restore, 16)
    $w2 = Kdu @('-prv', '20', '-dse', "$dec")
    Lg ('restore DSE 0x' + $restore + ' as decimal ' + $dec + ': ' + (($w2 -replace '\s+', ' ').Trim()))
    $post = $restore
}

if (-not $running) { Lg 'RESULT: FAIL - driver not running (577 = signature, see sc start above)'; Emit; exit 1 }

$epid = (Get-Process explorer | Select-Object -First 1).Id
$py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
$sc = Join-Path $root 'ext\qk_va.py'
$qout = Join-Path $here 'qk_va_drv1.txt'
Lg ('probe: explorer pid=' + $epid + ' -> ' + $qout)
& $py $sc ('--pid=' + $epid) '--pe' ('--out=' + $qout) '--no-elevate' | ForEach-Object { $L.Add('  ' + $_) ; Write-Host ('  ' + $_) }
Lg ('probe exit=' + $LASTEXITCODE)
Lg ('RESULT: driver=' + $running + ' dse_in=0x' + $pre + ' dse_out=0x' + $(if ($post) { $post } else { '?' }) + ' probe_rc=' + $LASTEXITCODE)
Emit
exit 0
