# p110_idle.ps1 -- keep the cores out of deep idle C-states, because that is
# exactly where the box now dies.
#
# Dump evidence (p109, _ritual\crashparse2.txt, 110526-11015-01.dmp):
#   BUGCHECK 124, MCi_STATUS = 0xfe000000_80113a  (VAL OVER UC EN MISCV ADDRV
#   PCC set, MCA code 0x113a = L2 cache), WHEA id=18 "Cache Hierarchy Error",
#   and the stack is:
#     intelppm!MWaitIdle+0x3f
#     intelppm!AcpiCStateIdleExecute+0x23
#     nt!PpmIdleExecuteTransition+0x518
#     nt!PoIdle -> nt!KiIdleLoop
#   i.e. the machine check fires while the core is being parked in MWAIT, not
#   during any of our reads.  APIC ID 48 (13:15, 13:27) and 25 (13:59), so it is
#   not one core only - the package-level idle path is the common factor.
#
# Variable: the active power scheme's SUB_PROCESSOR!IDLEDISABLE  0 -> 1
# (co-set, same intent: PROCTHROTTLEMIN 100 so cores never drop to a parked
# state and immediately re-enter it).  No boot flag, no driver, no CI - it is
# reversible in one command and takes effect on re-activating the scheme.
#
# R4: prior values are read back into temp\_p110_restore.txt before the write,
# and `-Restore` puts them back.
param([switch]$Restore)

$root = Split-Path -Parent $PSScriptRoot
$pre  = Join-Path $root 'temp\_p110_pre.txt'
$bak  = Join-Path $root 'temp\_p110_restore.txt'
$out  = Join-Path $root 'temp\_p110_out.txt'
$sub  = 'SUB_PROCESSOR'

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($Restore) { $a += ' -Restore' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    exit 0
}

# Read one AC setting (hex) out of the active scheme.  IDLEDISABLE is a HIDDEN
# setting, so `/query` returns only the scheme header - it must be `/qh`.
function GetAc([string]$alias) {
    $t = (powercfg /qh SCHEME_CURRENT $sub $alias) -join "`n"
    $m = [regex]::Match($t, '(?m)Current AC Power Setting Index:\s*(0x[0-9a-fA-F]+)')
    if ($m.Success) { return [Convert]::ToInt32($m.Groups[1].Value, 16) }
    return $null
}

$scheme = (powercfg /getactivescheme) -join ' '
$idle0  = GetAc 'IDLEDISABLE'
$min0   = GetAc 'PROCTHROTTLEMIN'

$msg = @()
$msg += ('pre ' + (Get-Date -f 'HH:mm:ss') + '  boot ' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
$msg += ('mode=' + $(if ($Restore) { 'RESTORE' } else { 'SET' }))
$msg += ('scheme=' + $scheme.Trim())
$msg += ('IDLEDISABLE ac before=' + $idle0)
$msg += ('PROCTHROTTLEMIN ac before=' + $min0)
$msg += ('restore file exists=' + (Test-Path -LiteralPath $bak))
$msg += ('bugchecks today=' + (@(Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; StartTime=(Get-Date).Date} -EA SilentlyContinue).Count))
($msg -join "`r`n") | Set-Content -LiteralPath $pre -Encoding UTF8

# R4: first-write-wins.  A second SET run must not overwrite the true prior
# values with the ones this script already wrote.
if (-not $Restore -and -not (Test-Path -LiteralPath $bak)) {
    @(
        ('idledisable_ac=' + $idle0)
        ('procthrottlemin_ac=' + $min0)
        ('note=IDLEDISABLE default is 0 (Enable idle); logon scheme was Balanced with min=5')
        ('restore_cmd=powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE ' + $(if ($null -eq $idle0) { 0 } else { $idle0 }) + '; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN ' + $(if ($null -eq $min0) { 5 } else { $min0 }) + '; powercfg /setactive SCHEME_CURRENT')
    ) | Set-Content -LiteralPath $bak -Encoding UTF8
}

$err = ''
try {
    if ($Restore) {
        powercfg /setacvalueindex SCHEME_CURRENT $sub IDLEDISABLE $(if ($null -eq $idle0) { 0 } else { $idle0 }) | Out-Null
        powercfg /setacvalueindex SCHEME_CURRENT $sub PROCTHROTTLEMIN $(if ($null -eq $min0) { 5 } else { $min0 }) | Out-Null
    } else {
        powercfg /setacvalueindex SCHEME_CURRENT $sub IDLEDISABLE 1 | Out-Null
        powercfg /setacvalueindex SCHEME_CURRENT $sub PROCTHROTTLEMIN 100 | Out-Null
        powercfg /setdcvalueindex SCHEME_CURRENT $sub IDLEDISABLE 1 | Out-Null
        powercfg /setdcvalueindex SCHEME_CURRENT $sub PROCTHROTTLEMIN 100 | Out-Null
    }
    powercfg /setactive SCHEME_CURRENT | Out-Null
} catch { $err = $_.Exception.Message }

$idle1 = GetAc 'IDLEDISABLE'
$min1  = GetAc 'PROCTHROTTLEMIN'
$want  = if ($Restore) { $idle0 } else { 1 }
$ok    = ($idle1 -eq $want)

$o = @()
$o += ('readback IDLEDISABLE ac=' + $idle1 + ' want=' + $want + ' min=' + $min1 + ' err=' + $err)
$o += ('RESULT IDLEDISABLE {0} -> {1} (min {2} -> {3}) rc_ok={4}' -f $idle0, $idle1, $min0, $min1, $ok)
$o += ('VERDICT ' + $(if ($ok) { 'IDLE_DISABLED' } else { 'IDLE_NOT_SET' }))
($o -join "`r`n") | Set-Content -LiteralPath $out -Encoding UTF8
Get-Content -LiteralPath $out
