# _p106_task.ps1 -- start p96_refresh.py as SYSTEM with an explicit page cap and resume PA.
#
# Same shape as _ritual\p38_task.ps1: SYSTEM principal (the interactive elevated
# token lacks SeLockMemoryPrivilege and a session-0 task survives a terminal
# teardown), self-elevating once for registration.  The resume PA is a parameter
# because p106a found a *contiguous* 4 MiB fault pocket at 0x2000000-0x203f000
# that ate the whole 64-page hop budget, so the next question (is the device
# alive at all?) needs its own start address and its own tag.
#
# One variable per run (R5): every tag has its own pre/task files, and the guest's
# OUT file is copied by hand to _p106<tag>_out.txt before the next start because
# p96 truncates it.
#
# Pre-state goes to _p106<tag>_pre.txt before anything starts, because a verdict
# without its "before" is not evidence (R3).
param(
    [int]$maxpages = 4000,
    [string]$resume = '0x300000',
    [string]$tag = 'a',
    [int]$hopmax = 0
)

$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$f = Join-Path $PSScriptRoot 'p96_refresh.py'
$pre = Join-Path $PSScriptRoot ('_p106' + $tag + '_pre.txt')
$log = Join-Path $PSScriptRoot ('_p106' + $tag + '_task.log')

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -maxpages ' + $maxpages + ' -resume ' + $resume + ' -tag ' + $tag) -Verb RunAs -Wait
    exit 0
}

$prog = Join-Path $PSScriptRoot '_p96_prog.txt'
$out = Join-Path $PSScriptRoot '_p96_refresh.txt'
$msg = @()
$msg += ('pre ' + (Get-Date -f 'HH:mm:ss'))
$msg += ('prog lines=' + (@(Get-Content -LiteralPath $prog -EA SilentlyContinue).Count))
$msg += ('out bytes=' + (@(Get-Item -LiteralPath $out -EA SilentlyContinue).Length))
$msg += ('out last=' + (@(Get-Content -LiteralPath $out -Tail 1 -EA SilentlyContinue) -join ''))
$taskn = 'QwenKern_p106' + $tag
$msg += ('task before=' + (@(Get-ScheduledTask -TaskName $taskn -EA SilentlyContinue) | ForEach-Object { $_.State }))
($msg -join "`r`n") | Set-Content -LiteralPath $pre -Encoding UTF8

$msg = @()
try {
    $a = New-ScheduledTaskAction -Execute $py -Argument ('"' + $f + '" ' + $maxpages + ' ' + $resume) -WorkingDirectory $PSScriptRoot
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskn -Action $a -Principal $p -Settings $s -Force -EA Stop | Out-Null
    $msg += ('registered SYSTEM, limit=PT1H, maxpages=' + $maxpages + ' resume=' + $resume)
    Start-ScheduledTask -TaskName $taskn
    Start-Sleep -Seconds 4
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName $taskn).State)
    $msg += ('lastRun=' + (Get-ScheduledTaskInfo -TaskName $taskn).LastRunTime)
} catch { $msg += ('FAILED: ' + $_.Exception.Message) }
($msg -join "`r`n") | Set-Content -LiteralPath $log -Encoding UTF8
Get-Content -LiteralPath $log -Tail 6
