$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\vmcheck.txt'
function S($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
S ("now        = " + (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
S ("tz         = " + (Get-TimeZone).Id + "  utc=" + (Get-Date).ToUniversalTime().ToString('dd/MM/yyyy HH:mm:ss'))
$os = Get-CimInstance Win32_OperatingSystem
S ("lastboot   = " + $os.LastBootUpTime)
S ("uptime     = " + ((Get-Date) - $os.LastBootUpTime))
S ("host       = " + $env:COMPUTERNAME + "  model=" + (Get-CimInstance Win32_ComputerSystem).Model +
   "  ram=" + [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) + "GB")
S ''
S '--- test mode / boot flags ---'
S ((bcdedit /enum '{current}' 2>&1) -join "`r`n")
S ''
S '--- p36 artefacts (LastWriteTime only) ---'
S ((Get-ChildItem 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p36*',
      'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_p36*' -EA 0 |
    Sort-Object LastWriteTime -Descending |
    Select-Object LastWriteTime, Length, Name | Format-Table -AutoSize | Out-String))
S '--- scheduled task state (Last Result 267009 = still running) ---'
S ((schtasks /query /tn QwenKern_p36 /v /fo LIST 2>&1) | Select-String -Pattern 'Last Run Time|Last Result|Status|Run As|Task To Run' | Out-String)
S '--- p36 process alive? ---'
S ((Get-Process powershell, csc -EA 0 | Select-Object Id, StartTime, ProcessName |
    Format-Table -AutoSize | Out-String))
S '--- task log tail ---'
S ((Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_p36_task.log' -Tail 8 -EA 0) -join "`r`n")
S ''
S '--- bugchecks / unexpected shutdowns (System log) ---'
S ((Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001,41,6008} -MaxEvents 12 -EA 0 |
    ForEach-Object { $_.TimeCreated.ToString('dd/MM HH:mm:ss') + '  id=' + $_.Id + '  ' +
      (($_.Message -split "`n")[0..1] -join ' ') }) -join "`r`n")
S ''
S '--- minidumps ---'
S ((Get-ChildItem 'C:\Windows\Minidump' -EA 0 | Sort-Object LastWriteTime -Descending |
    Select-Object -First 8 LastWriteTime, Length, Name | Format-Table -AutoSize | Out-String))
S '--- debugger available? ---'
S (('kd: ' + ((Get-Command kd.exe -EA 0).Source)) + '  windbg: ' + ((Get-Command windbg.exe -EA 0).Source))
S ''
S '--- our providers / candidate 3rd-party kernel modules ---'
S ((Get-ChildItem 'C:\Windows\System32\drivers' -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv|msio|apex|mb|ntiolib|winio' } |
    Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String))
S ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv|msio|apex|eas|javelin|BEDaisy|EasyAnti' } |
    Select-Object Name, State, StartMode, PathName | Format-Table -AutoSize | Out-String))
S ''
S '--- hypervisor / VM tooling on the host ---'
S ((Get-Service vmms, vmcompute, VBoxSup, VBoxDrv, VMUSBArbService, VMwareHostd -EA 0 |
    Select-Object Name, Status, StartType | Format-Table -AutoSize | Out-String))
S (('vmrun: ' + ((Get-Command vmrun.exe -EA 0).Source)) +
   '  VBoxManage: ' + ((Get-Command VBoxManage.exe -EA 0).Source) +
   '  vmconnect: ' + ((Get-Command vmconnect.exe -EA 0).Source))
S '--- .vmx / .vmcx found ---'
$roots = @('C:\Users\New User\Documents\Virtual Machines', 'C:\Users\New User\Virtual Machines',
           'C:\Users\New User\OneDrive\Desktop', 'C:\VMs', 'D:\VMs', 'C:\ProgramData\Microsoft\Windows\Hyper-V')
S (($roots | ForEach-Object {
      Get-ChildItem -LiteralPath $_ -Recurse -Depth 3 -Include *.vmcx, *.vmx, *.vbox -EA 0 |
      Select-Object -First 20 | ForEach-Object { $_.FullName } }) -join "`r`n")
S ''
S '--- hypervisorlaunchtype (does the HOST run Hyper-V?) ---'
S ((bcdedit /enum '{current}' 2>&1 | Select-String -Pattern 'hypervisorlaunchtype') | Out-String)
S '--- done ---'
