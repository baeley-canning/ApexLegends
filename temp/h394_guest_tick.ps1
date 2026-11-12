# Guest-only, no host state. Reads a self-owned process, restores service.
$log = 'C:\p37tick_h394.log'
Remove-Item -LiteralPath C:\h394_watch_done -EA SilentlyContinue
$ErrorActionPreference='Continue'
'device: '+$env:COMPUTERNAME | Set-Content C:\p37tick_h394.log
'start '+env:NUMBER_OF_PROCESSORS | Add-Content $log
Get-Process powershell | Select-Object Id,StartTime | Out-String | Add-Content C:\h394_watch.log
schtasks /query /tn QwenKern_h394 /xml 2>&1 | Out-String | Set-Content C:\h394_task.xml
'guest tick waiting for h394 input' | Add-Content $log
if ($false) { return }