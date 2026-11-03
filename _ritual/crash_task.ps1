# crash_task.ps1 - self-elevate, register crash_kd.ps1 as a HIGHEST task, run it.
# Same pattern as p36_task.ps1 (the tool console cannot be trusted to stay alive).
$f   = Join-Path $PSScriptRoot 'crash_kd.ps1'
$log = Join-Path $PSScriptRoot '_crash_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

if (-not $adm) {
    "$(Get-Date -f 'dd/MM/yyyy HH:mm:ss') self-elevating (UAC)" | Set-Content -LiteralPath $log
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    Get-Content -LiteralPath $log -Tail 5
    exit 0
}
"$(Get-Date -f 'dd/MM/yyyy HH:mm:ss') register-run target=$f" | Set-Content -LiteralPath $log
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"')
    $p = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'QwenKern_crash' -Action $a -Principal $p -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName 'QwenKern_crash'
    ('started, state=' + (Get-ScheduledTask -TaskName 'QwenKern_crash').State) | Add-Content -LiteralPath $log
} catch { ('FAILED: ' + $_.Exception.Message) | Add-Content -LiteralPath $log }
Get-Content -LiteralPath $log -Tail 5
