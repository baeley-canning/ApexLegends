# _p107g_gio.ps1 -- run the read-path health probe as SYSTEM (device DACL is
# SYSTEM+BA, so an unelevated shell cannot even open it).
#
# Read-only: Gio opens, reads, closes.  Nothing on the box changes, so there is no
# restore leg (R4 vacuous) and it is safe to re-run.  Pre-state still gets written
# (R3: the pre/post halves are the receipt) -- task state, whether the previous
# p107a task is still registered, and the last prog line of the last run.
#
# -Inner is what the SYSTEM task starts; the default mode self-elevates, registers
# QwenKern_p107g and starts it.  Result goes to _p107g_task.log.
param([switch]$Inner)

$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$f = Join-Path $PSScriptRoot '_p107g_gio.py'
$taskn = 'QwenKern_p107g'

if ($Inner) {
    & $py $f
    exit $LASTEXITCODE
}

$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    exit 0
}

$pre = Join-Path $PSScriptRoot '_p107g_pre.txt'
$log = Join-Path $PSScriptRoot '_p107g_task.log'
# Stage markers: the box bugchecked 0..3 s after the pre file twice (13:14:56,
# 13:58:30) and the task store lost the registration both times, so "it never
# ran" cannot be told apart from "it ran and the log was never written".
# Add-Content emits nothing, so calling st bare cannot pollute a return value.
$pt = Join-Path $PSScriptRoot '_p107g_stage.txt'
function st([string]$s) { ((Get-Date -f 'HH:mm:ss') + ' ' + $s) | Add-Content -LiteralPath $pt -Encoding UTF8 }
st 'enter'
$msg = @()
$msg += ('pre ' + (Get-Date -f 'HH:mm:ss'))
$msg += ('out exists before=' + (Test-Path -LiteralPath (Join-Path $PSScriptRoot '_p107g_out.txt')))
$msg += ('prog last=' + (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '_p96_prog.txt') -Tail 1 -EA SilentlyContinue) -join ''))
$msg += ('task before=' + ((@(Get-ScheduledTask -TaskName $taskn -EA SilentlyContinue) | ForEach-Object { $_.State }) -join ','))
$msg += ('gio.py lines=' + (@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\ext\gio.py')).Count))
($msg -join "`r`n") | Set-Content -LiteralPath $pre -Encoding UTF8
st 'pre written'

$msg = @()
try {
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Inner'
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $PSScriptRoot
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    st 'registering'
    Register-ScheduledTask -TaskName $taskn -Action $a -Principal $p -Settings $s -Force -EA Stop | Out-Null
    $msg += 'registered SYSTEM, limit=PT5M'
    st 'registered'
    Start-ScheduledTask -TaskName $taskn
    st 'started'
    Start-Sleep -Seconds 3
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName $taskn).State)
    st 'slept'
} catch { $msg += ('FAILED: ' + $_.Exception.Message); st ('FAILED ' + $_.Exception.Message) }
($msg -join "`r`n") | Set-Content -LiteralPath $log -Encoding UTF8
st 'log written'
Get-Content -LiteralPath $log -Tail 6
