# ============================================================================
# _ritual\qk_drv_cameo.ps1 - apexdrv appears for ~2 s to hand over DTB + base, then leaves.
#
# Why: the CONTROL proved a resident apexdrv alone kills the game (53 s, zero reads),
# and pure-gdrv3 discovery does not resolve the DTB (4100 table-shaped frames, 0 PE).
# The DTB and the image base are valid for the whole life of the process, so one
# short visit at the start of a session is enough - and nothing of ours is resident
# while the game is actually being played.
#
# Order (R3/R4): DSE read/write 0 -> sc start -> probe (~2 s) -> sc stop -> DSE restore.
# ============================================================================
[CmdletBinding()]
param([string] $OutFile = '')

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
if (-not $OutFile) { $OutFile = Join-Path $here 'qk_cameo.out' }

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

Lg '===== apexdrv cameo (DTB + base, then gone) ====='
$game = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) { Lg 'RESULT: FAIL - no game'; Emit; exit 1 }
Lg ('game pid=' + $game.Id)

# DSE: kdu's bare -dse WRITES 0, so the "read" is the write we want; the value it
# prints is the prior one, which is what we restore at the end (as DECIMAL).
$w = Kdu @('-prv', '20', '-dse', '0')
$pre = ''
if ($w -match 'value:\s*([0-9A-Fa-f]+)') { $pre = $matches[1] }
Lg ('DSE pre=0x' + $(if ($pre) { $pre } else { '?' }) + ' -> wrote 0')
Start-Sleep -Milliseconds 400

$s = & sc.exe start ApexDrv 2>&1 | Out-String
Lg ('sc start: ' + (($s -replace '\s+', ' ').Trim()))

$py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
$sc = Join-Path $root 'ext\qk_va.py'
$qout = Join-Path $here 'qk_va_cameo.txt'
& $py $sc ('--pid=' + $game.Id) '--pe' ('--out=' + $qout) '--no-elevate' | ForEach-Object { Lg ('  | ' + $_) }

$st = & sc.exe stop ApexDrv 2>&1 | Out-String
Lg ('sc stop: ' + (($st -replace '\s+', ' ').Trim()))
$q = & sc.exe query ApexDrv 2>&1 | Out-String
Lg ('driver now: ' + (($q | Select-String 'STATE').Line.Trim()))

if ($pre -and $pre -match '^[0-9A-Fa-f]+$' -and $pre -notmatch '^0+$') {
    $dec = [Convert]::ToInt32($pre, 16)
    $w2 = Kdu @('-prv', '20', '-dse', "$dec")
    $ok = ($w2 -match 'verification succeeded')
    Lg ('DSE restore to 0x' + $pre + ' (decimal ' + $dec + '): verified=' + $ok)
}
Lg ('game still alive=' + [bool](Get-Process -Id $game.Id -ErrorAction SilentlyContinue))
Lg ('RESULT: cameo done; log ' + $qout)
Emit
exit 0
