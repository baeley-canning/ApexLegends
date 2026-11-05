# _p107_edge.ps1 -- find both edges of the fault pocket with a strided hop.
#
# p106w settled the shape of the fault: 0x10000000 -> 0x1400f000, 16384 HOP lines,
# one per page, hits=0.  It is one contiguous pocket of at least 64 MiB, not a pin
# and not a dead device (the low 2 MiB still reads clean), and a 1-page hop spends
# 16k faults to learn nothing but "still dead".  So the hop gets a width:
#
#   dl.HOP_STRIDE (GIO_HOP_STRIDE) probes every Nth page *while pages are lost*
#   and drops back to one page the moment one reads.  The walk therefore crosses
#   the pocket at N pages per hop and, at the far edge, turns into a normal dense
#   sweep -- hits start landing there, which is the thing this probe owes a live
#   read.
#
# Two modes in one file: -Inner runs python under the env knobs (that is what the
# SYSTEM task starts); the default mode self-elevates, registers QwenKern_p107<tag>
# as SYSTEM and starts it.  Pre-state goes to _p107<tag>_pre.txt before the start
# (R3), task result to _p107<tag>_task.log; the guest's own out/prog files are
# `_p96*` and are copied off by hand before the next tag (R5).
param(
    [int]$maxpages = 600,
    [string]$resume = '0x2000000',
    [int]$stride = 64,
    [int]$hop = 2048,
    [string]$tag = 'a',
    [switch]$Inner
)

$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$f = Join-Path $PSScriptRoot 'p96_refresh.py'
$taskn = 'QwenKern_p107' + $tag

if ($Inner) {
    $env:GIO_HOP_MAX = [string]$hop
    $env:GIO_HOP_STRIDE = [string]$stride
    & $py $f $maxpages $resume
    exit $LASTEXITCODE
}

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -maxpages ' + $maxpages + ' -resume ' + $resume + ' -stride ' + $stride + ' -hop ' + $hop + ' -tag ' + $tag
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    exit 0
}

$pre = Join-Path $PSScriptRoot ('_p107' + $tag + '_pre.txt')
$log = Join-Path $PSScriptRoot ('_p107' + $tag + '_task.log')
$msg = @()
$msg += ('pre ' + (Get-Date -f 'HH:mm:ss'))
$msg += ('prog lines=' + (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '_p96_prog.txt') -EA SilentlyContinue).Count))
$msg += ('out last=' + (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '_p96_refresh.txt') -Tail 1 -EA SilentlyContinue) -join ''))
$msg += ('task before=' + (@(Get-ScheduledTask -TaskName $taskn -EA SilentlyContinue) | ForEach-Object { $_.State }))
$msg += ('args maxpages=' + $maxpages + ' resume=' + $resume + ' GIO_HOP_STRIDE=' + $stride + ' GIO_HOP_MAX=' + $hop)
($msg -join "`r`n") | Set-Content -LiteralPath $pre -Encoding UTF8

$msg = @()
try {
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Inner -maxpages ' + $maxpages + ' -resume ' + $resume + ' -stride ' + $stride + ' -hop ' + $hop + ' -tag ' + $tag
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $PSScriptRoot
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskn -Action $a -Principal $p -Settings $s -Force -EA Stop | Out-Null
    $msg += ('registered SYSTEM, limit=PT1H, stride=' + $stride + ' hop=' + $hop)
    Start-ScheduledTask -TaskName $taskn
    Start-Sleep -Seconds 4
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName $taskn).State)
    $msg += ('lastRun=' + (Get-ScheduledTaskInfo -TaskName $taskn).LastRunTime)
} catch { $msg += ('FAILED: ' + $_.Exception.Message) }
($msg -join "`r`n") | Set-Content -LiteralPath $log -Encoding UTF8
Get-Content -LiteralPath $log -Tail 6
