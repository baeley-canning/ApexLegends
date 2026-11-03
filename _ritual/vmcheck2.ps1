$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\vmcheck2.txt'
function S($t) { try { $t | Out-File -FilePath $o -Encoding ascii -Append } catch {} }
if (Test-Path $o) { Remove-Item $o -Force }
function Try-S($label, $sb) { S ("--- $label ---"); try { S (& $sb) } catch { S ("  ERR: " + $_.Exception.Message) }; S '' }

S ("now        = " + (Get-Date -f 'dd/MM/yyyy HH:mm:ss') + "   utc=" + (Get-Date).ToUniversalTime().ToString('HH:mm:ss'))
$os = Get-CimInstance Win32_OperatingSystem
S ("lastboot   = " + $os.LastBootUpTime + "   uptime=" + ((Get-Date) - $os.LastBootUpTime))
S ("elevated   = " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
S ("startopts  = " + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -EA 0).SystemStartOptions)
S ("safe-mode? = " + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Option' -EA 0).OptionValue)

Try-S 'bcdedit raw' { (& bcdedit /enum all) 2>&1 | Select-String -Pattern 'identifier|testsigning|hypervisorlaunchtype|nointegritychecks|description' }
Try-S 'artefacts (name/size/time)' {
  Get-ChildItem 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual' -EA 0 |
    Where-Object { $_.Name -match '^(p3[0-9]|_p3)' } | Sort-Object LastWriteTime -Descending | Select-Object -First 20 |
    ForEach-Object { '{0}  {1,9}  {2}' -f $_.LastWriteTime.ToString('dd/MM HH:mm:ss'), $_.Length, $_.Name } }
Try-S 'task csv' { (schtasks /query /tn QwenKern_p36 /v /fo csv) 2>&1 | ConvertFrom-Csv |
  Select-Object 'Last Run Time','Last Result','Status','Next Run Time' | Format-List | Out-String }
Try-S 'p36_write.txt (full)' { Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p36_write.txt' -EA 0 }
Try-S 'p36_write.txt bytes' { $b = [IO.File]::ReadAllBytes('C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p36_write.txt'); "len=$($b.Length) first16=" + (($b[0..15] | ForEach-Object { $_.ToString('x2') }) -join ' ') }
Try-S 'p36_check2.txt bytes' { $b = [IO.File]::ReadAllBytes('C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p36_check2.txt'); "len=$($b.Length) first32=" + (($b[0..31] | ForEach-Object { $_.ToString('x2') }) -join ' ') }
Try-S 'minidumps' { Test-Path 'C:\Windows\Minidump'; (Get-ChildItem 'C:\Windows\Minidump' -EA 0 | Select-Object -Last 6 | ForEach-Object { $_.Name + '  ' + $_.Length }) }
Try-S 'WER reports (today)' {
  Get-ChildItem 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive','C:\ProgramData\Microsoft\Windows\WER\ReportQueue' -Directory -EA 0 |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-6) } | Select-Object -First 12 |
    ForEach-Object { $_.FullName } }
Try-S 'WER Report.wer hits for our report id' {
  Get-ChildItem 'C:\ProgramData\Microsoft\Windows\WER' -Recurse -Filter 'Report.wer' -EA 0 |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-6) } | Select-Object -First 6 |
    ForEach-Object { '== ' + $_.FullName; (Select-String -Path $_.FullName -Pattern 'Sig\[|AppName|AppPath|ReportIdentifier' -EA 0 | Select-Object -First 12 | ForEach-Object { $_.Line }) } }
Try-S 'debuggers on disk' {
  @('C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe',
    'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\windbg.exe',
    'C:\Program Files\Windows Kits\10\Debuggers\x64\kd.exe',
    'C:\Program Files\WindowsApps\Microsoft.WinDbg*\WinDbgX.exe') | ForEach-Object { $_ + '  ' + (Test-Path $_) } }
Try-S 'VirtualBox install' {
  @('C:\Program Files\Oracle\VirtualBox\VBoxManage.exe',
    'C:\Program Files\Oracle\VirtualBox\VirtualBox.exe',
    'C:\Program Files\Oracle\VirtualBox\VBoxSVC.exe') | ForEach-Object { $_ + '  ' + (Test-Path $_) }
  'VBoxSup svc: ' + ((Get-Service VBoxSup -EA 0).Status)
  'user registry: ' + (Test-Path "$env:USERPROFILE\.VirtualBox\VirtualBox.xml") }
Try-S 'virtualbox VMs (registry xml)' {
  $p = "$env:USERPROFILE\.VirtualBox\VirtualBox.xml"
  if (Test-Path $p) { (Select-String -Path $p -Pattern 'MachineEntry' | ForEach-Object { $_.Line.Trim() }) } else { 'no VirtualBox.xml' } }
Try-S 'VirtualBox VMs on disk' {
  Get-ChildItem "$env:USERPROFILE" -Directory -EA 0 | Where-Object { $_.Name -match 'VirtualBox' } | ForEach-Object { $_.FullName }
  Get-ChildItem 'C:\Users\New User\VirtualBox VMs','D:\VirtualBox VMs' -Recurse -Depth 2 -Filter '*.vbox' -EA 0 | ForEach-Object { $_.FullName } }
Try-S 'vboxmanage list vms' { & 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' list vms 2>&1 }
Try-S 'vboxmanage list runningvms' { & 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' list runningvms 2>&1 }
Try-S 'hyper-v side' {
  'vmms svc: ' + ((Get-Service vmms -EA 0).Status)
  'vmcompute svc: ' + ((Get-Service vmcompute -EA 0).Status)
  'C:\ProgramData\Microsoft\Windows\Hyper-V: ' + (Test-Path 'C:\ProgramData\Microsoft\Windows\Hyper-V')
  Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Hyper-V' -EA 0 | Select-Object -First 10 | ForEach-Object { $_.Name } }
Try-S 'drivers we care about (state/path)' {
  Get-CimInstance Win32_SystemDriver -EA 0 | Where-Object { $_.Name -match 'gdrv3|MSIO|apexdrv' } |
    ForEach-Object { '{0} state={1} start={2} path={3}' -f $_.Name, $_.State, $_.StartMode, $_.PathName } }
S '--- end ---'
