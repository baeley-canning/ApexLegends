$ErrorActionPreference = 'Continue'
$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o = Join-Path $r 'p13_boot.txt'
function W($s) { $s | Add-Content -LiteralPath $o }
function Sec($s) { W ''; W ('########## ' + $s + ' ##########') }
function Prop($k) { W ('---- ' + $k); W ((Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | Out-String -Width 260)) }
if (Test-Path $o) { Remove-Item $o -Force }
W ('=== p13 boot/CI probe ' + (Get-Date) + ' ===')

Sec '[1] elevation / OS / firmware / secure boot'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
W ('user: ' + $id.Name + ' | isAdmin: ' + $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$os = Get-CimInstance Win32_OperatingSystem
W ('os: ' + $os.Caption + ' | build ' + $os.BuildNumber + ' | ver ' + $os.Version)
W ('bootdevice: ' + $os.BootDevice + ' | systemdrive ' + $os.SystemDrive)
try { W ('SecureBootUEFI: ' + (Confirm-SecureBootUEFI)) } catch { W ('SecureBootUEFI ERR: ' + $_.Exception.Message) }
try { W ('PEFirmwareType (1=BIOS 2=UEFI): ' + (Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop)) } catch { W ('PEFirmwareType ERR: ' + $_.Exception.Message) }
try { W ('SystemStartOptions: ' + (Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction Stop)) } catch { W ('SystemStartOptions ERR: ' + $_.Exception.Message) }
try { W ('SystemBootDevice: ' + (Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemBootDevice -ErrorAction Stop)) } catch { W ('SystemBootDevice ERR: ' + $_.Exception.Message) }

Sec '[2] CI / boot reg trees'
foreach ($k in @('HKLM:\SYSTEM\CurrentControlSet\Control\CI', 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy', 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\State', 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management', 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot', 'HKLM:\SYSTEM\CurrentControlSet\Control\WdBoot')) { Prop $k }

Sec '[3] CI policies via WMI'
try { W ((Get-CimInstance -Namespace 'root\Microsoft\Windows\CI' -ClassName MSFT_CIPolicy -ErrorAction Stop | Format-List * | Out-String -Width 260)) } catch { W ('MSFT_CIPolicy ERR: ' + $_.Exception.Message) }
try { W ((Get-CimInstance -Namespace 'root\Microsoft\Windows\CI' -ClassName MSFT_CIPolicyFile -ErrorAction Stop | Format-List * | Out-String -Width 260)) } catch { W ('MSFT_CIPolicyFile ERR: ' + $_.Exception.Message) }

Sec '[4] CodeIntegrity policy files on disk'
foreach ($p in @('C:\Windows\System32\CodeIntegrity', 'C:\Windows\System32\CodeIntegrity\CiPolicies', 'C:\Windows\System32\CodeIntegrity\CiPolicies\Active')) {
  if (-not (Test-Path -LiteralPath $p)) { W ('MISSING ' + $p); continue }
  W ('---- ' + $p)
  W ((Get-ChildItem -LiteralPath $p -Force -Recurse -Depth 1 -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))
}

Sec '[5] eaanticheat / skyfall / javelin file hunt'
foreach ($p in @('C:\Windows\System32\drivers', 'C:\Program Files\EA\AC', 'C:\ProgramData\eaanticheat', 'C:\Windows\Temp', (Join-Path $env:LOCALAPPDATA 'Electronic Arts'), (Join-Path $env:LOCALAPPDATA 'EAAntiCheat'), (Join-Path $env:APPDATA 'EAAntiCheat'))) {
  if (-not (Test-Path -LiteralPath $p)) { W ('MISSING ' + $p); continue }
  W ('---- ' + $p)
  W ((Get-ChildItem -LiteralPath $p -Force -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))
}
W '---- whole-drive eaanticheat* (depth 6)'
W ((Get-ChildItem 'C:\' -Recurse -Force -Depth 6 -Filter 'eaanticheat*' -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))
W '---- whole-drive *javelin* (depth 6)'
W ((Get-ChildItem 'C:\' -Recurse -Force -Depth 6 -Filter '*javelin*' -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))
W '---- whole-drive *skyfall* (depth 6)'
W ((Get-ChildItem 'C:\' -Recurse -Force -Depth 6 -Filter '*skyfall*' -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))

Sec '[6] service config + state'
foreach ($s in @('EAAntiCheat', 'EAAntiCheatService', 'apexdrv', 'EasyAntiCheat_EOS')) {
  W ('---- sc qc ' + $s)
  W ((cmd /c "sc qc $s 2>&1" | Out-String))
  W ('---- sc query ' + $s)
  W ((cmd /c "sc query $s 2>&1" | Out-String))
}

Sec '[7] CodeIntegrity / CodeIntegrity-Operational event log (3 days)'
$ci = Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = (Get-Date).AddDays(-3)} -ErrorAction SilentlyContinue
if ($ci) { W ((($ci | Select-Object -First 80 TimeCreated, Id, LevelDisplayName, Message) | Format-Table -Wrap | Out-String -Width 300)) } else { W 'no CI/Operational events' }

Sec '[8] System log, CodeIntegrity provider (3 days)'
$sy = Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = (Get-Date).AddDays(-3); ProviderName = 'Microsoft-Windows-CodeIntegrity'} -ErrorAction SilentlyContinue
if ($sy) { W ((($sy | Select-Object -First 40 TimeCreated, Id, LevelDisplayName, Message) | Format-Table -Wrap | Out-String -Width 300)) } else { W 'no System/CodeIntegrity events' }

Sec '[9] Application log matches javelin|anticheat|skyfall (6h)'
$ap = Get-WinEvent -FilterHashtable @{LogName = 'Application'; StartTime = (Get-Date).AddHours(-6)} -ErrorAction SilentlyContinue
if ($ap) { W ((($ap | Where-Object { $_.Message -match '(?i)javelin|anticheat|skyfall|gameservice' } | Select-Object -First 40 TimeCreated, Id, ProviderName, LevelDisplayName, Message) | Format-Table -Wrap | Out-String -Width 300)) } else { W 'no Application events' }

Sec '[10] WER report dirs + EA Desktop log dir'
foreach ($p in @('C:\ProgramData\Microsoft\Windows\WER\ReportArchive', 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue', (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'), 'C:\ProgramData\EA Desktop\Logs', (Join-Path $env:LOCALAPPDATA 'Electronic Arts\EA Desktop\Logs'))) {
  if (-not (Test-Path -LiteralPath $p)) { W ('MISSING ' + $p); continue }
  W ('---- ' + $p)
  W ((Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)ea|javelin|skyfall|anticheat' } | Select-Object -First 40 Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))
}
W ('=== DONE ' + (Get-Date) + ' ===')
