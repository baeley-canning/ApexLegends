# _p106_wide.ps1 -- measure the fault pocket's far edge with a wide hop budget.
#
# p106a/b/c established the pocket but not its extent: 0x2000000-0x207f000 is dead
# on every page and each run burns the whole 64-page budget before anything reads
# (three runs, two start addresses, same signature; the low 2 MiB reads clean, so
# the device is alive and the badpa grid is simply stale -- it ends at 0x2000000,
# which is where the pocket now begins).
#
# dl.HOP_MAX is `int(os.environ["GIO_HOP_MAX"] or "64")`, so the budget can be
# raised without touching code.  16384 hops cover 64 MiB, which is the widest
# window worth one UAC click: if the pocket is smaller, the walk resumes on good
# RAM and lands hits; if it is still dead at 0x6000000 the run stops there and the
# SCANSTOP pa *is* the edge measurement.  Worst case ~80 s (16k faults at ~5 ms).
#
# Two modes in one file: -Inner runs python (that is what the task starts), the
# default mode self-elevates, registers QwenKern_p106w as SYSTEM and starts it.
param(
    [int]$maxpages = 600,
    [string]$resume = '0x2000000',
    [int]$hop = 16384,
    [switch]$Inner
)

$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$f = Join-Path $PSScriptRoot 'p96_refresh.py'
$log = Join-Path $PSScriptRoot '_p106w_task.log'
$pre = Join-Path $PSScriptRoot '_p106w_pre.txt'

if ($Inner) {
    $env:GIO_HOP_MAX = [string]$hop
    & $py $f $maxpages $resume
    exit $LASTEXITCODE
}

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -maxpages ' + $maxpages + ' -resume ' + $resume + ' -hop ' + $hop) -Verb RunAs -Wait
    exit 0
}

$msg = @()
$msg += ('pre ' + (Get-Date -f 'HH:mm:ss'))
$msg += ('prog lines=' + (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '_p96_prog.txt') -EA SilentlyContinue).Count))
$msg += ('out last=' + (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '_p96_refresh.txt') -Tail 1 -EA SilentlyContinue) -join ''))
$msg += ('args maxpages=' + $maxpages + ' resume=' + $resume + ' GIO_HOP_MAX=' + $hop)
($msg -join "`r`n") | Set-Content -LiteralPath $pre -Encoding UTF8

$msg = @()
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Inner -maxpages ' + $maxpages + ' -resume ' + $resume + ' -hop ' + $hop) -WorkingDirectory $PSScriptRoot
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'QwenKern_p106w' -Action $a -Principal $p -Settings $s -Force -EA Stop | Out-Null
    $msg += 'registered SYSTEM, limit=PT1H, inner mode'
    Start-ScheduledTask -TaskName 'QwenKern_p106w'
    Start-Sleep -Seconds 4
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName 'QwenKern_p106w').State)
    $msg += ('lastRun=' + (Get-ScheduledTaskInfo -TaskName 'QwenKern_p106w').LastRunTime)
} catch { $msg += ('FAILED: ' + $_.Exception.Message) }
($msg -join "`r`n") | Set-Content -LiteralPath $log -Encoding UTF8
Get-Content -LiteralPath $log -Tail 6
