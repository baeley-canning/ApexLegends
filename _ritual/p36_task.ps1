# p36_task.ps1 - register + start p36_write.ps1 as a scheduled task at HIGHEST privileges.
#
# Why: (1) the \\.\GIOV3 and \\.\MSIO device DACLs require admin, and
#      \Device\PhysicalMemory needs admin + SeLockMemoryPrivilege; (2) the tool
#      console can be torn down between commands, killing any child process.
# A scheduled task is owned by the Task Scheduler service, so the run survives
# everything, and -RunLevel Highest means no second UAC prompt.
#
# This script self-elevates (one UAC approval) when registration needs it.
$f   = Join-Path $PSScriptRoot 'p36_write.ps1'
$log = Join-Path $PSScriptRoot '_p36_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

if (-not $adm) {
    "$(Get-Date -f 'dd/MM/yyyy HH:mm:ss') self-elevating (UAC) target=$f" | Set-Content -LiteralPath $log
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait
    Get-Content -LiteralPath $log -Tail 20
    exit 0
}

"$(Get-Date -f 'dd/MM/yyyy HH:mm:ss') register-run admin=$adm target=$f" | Set-Content -LiteralPath $log
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"')
    $p = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'QwenKern_p36' -Action $a -Principal $p -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName 'QwenKern_p36'
    Start-Sleep -Seconds 3
    ('started, state=' + (Get-ScheduledTask -TaskName 'QwenKern_p36').State) | Add-Content -LiteralPath $log
} catch {
    ('FAILED: ' + $_.Exception.Message) | Add-Content -LiteralPath $log
}
Get-Content -LiteralPath $log -Tail 20
