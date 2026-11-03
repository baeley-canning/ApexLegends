# tick.ps1 - install a 1-minute SYSTEM tick task so probes fire without any console
$d = 'C:\Users\Public\p37'
$log = "$d\tick.log"
$base = 'http://10.0.2.2:8080'
"tick install " + (Get-Date -f 'HH:mm:ss') | Set-Content -LiteralPath $log
& schtasks.exe /create /tn p37tick /tr "$d\run.cmd" /sc minute /mo 1 /ru SYSTEM /rl highest /f *>> $log
& schtasks.exe /create /tn p37logon /tr "$d\run.cmd" /sc onlogon /ru SYSTEM /rl highest /f *>> $log
& schtasks.exe /delete /tn p37run /f *>> $log
& schtasks.exe /query /fo csv *>> $log
& schtasks.exe /run /tn p37tick *>> $log
try { (New-Object Net.WebClient).UploadString("$base/log", ("## tick`r`n" + (Get-Content -LiteralPath $log -Raw))) } catch { }
