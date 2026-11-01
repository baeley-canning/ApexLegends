$ErrorActionPreference = 'SilentlyContinue'
$root = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out  = Join-Path $root 'p11_logs.txt'
function W { param([string]$t) $t | Out-File -FilePath $out -Append -Encoding utf8 }
function Section { param([string]$t) W ''; W ('###### ' + $t + ' ######') }
function ReadText { param([string]$p)
  $b = [IO.File]::ReadAllBytes($p)
  if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [Text.Encoding]::Unicode.GetString($b) }
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [Text.Encoding]::UTF8.GetString($b) }
  $nul = 0; $lim = [Math]::Min(4000, $b.Length)
  for ($i = 1; $i -lt $lim; $i += 2) { if ($b[$i] -eq 0) { $nul++ } }
  if ($nul -gt ([int]($lim / 8))) { return [Text.Encoding]::Unicode.GetString($b) }
  return [Text.Encoding]::ASCII.GetString($b)
}
function Head { param([string]$p, [int]$n = 60)
  try { $t = ReadText $p } catch { W '  (unreadable)'; return }
  $t = $t -replace "`r`n", "`n"
  $lines = $t -split "`n"
  W (($lines | Select-Object -First $n) -join "`r`n")
}
function Tree { param([string]$p)
  if (-not (Test-Path -LiteralPath $p)) { W ('MISSING: ' + $p); return }
  W ((Get-ChildItem -LiteralPath $p -Recurse -Force | Select-Object FullName, Length, LastWriteTime | Sort-Object LastWriteTime -Descending | Format-Table -AutoSize | Out-String -Width 400))
}

"=== p11 logs snapshot $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $out -Encoding utf8

Section '[1] C:\ProgramData\eaanticheat (recursive)'
Tree 'C:\ProgramData\eaanticheat'

Section '[2] eaanticheat small files (head 60 lines each)'
Get-ChildItem 'C:\ProgramData\eaanticheat' -Recurse -Force -File | Where-Object { $_.Length -lt 500000 } | Sort-Object LastWriteTime -Descending | Select-Object -First 25 | ForEach-Object {
  W ('---- ' + $_.FullName + '  (' + $_.Length + ' bytes, ' + $_.LastWriteTime + ') ----')
  Head $_.FullName 60
}

Section '[3] C:\Program Files\EA\AC (recursive)'
Tree 'C:\Program Files\EA\AC'

Section '[4] C:\Program Files\Electronic Arts (recursive)'
Tree 'C:\Program Files\Electronic Arts'

Section '[5] services registry entries matching ea|javelin|anti|apex|tv|team'
W ((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object { $_.PSChildName -match '(?i)ea|javelin|anti|apex|tv|team' } | ForEach-Object { $k = $_; $ip = (Get-ItemProperty $k.PSPath -Name ImagePath).ImagePath; '{0} | {1}' -f $k.PSChildName, $ip }) | Out-String -Width 300)

Section '[6] Win32_SystemDriver matching ea|javelin|ac|tv|team|gdrv|npcap|vbox|msio|ctiio|qwen'
W ((Get-CimInstance Win32_SystemDriver | Where-Object { $_.PathName -match '(?i)ea|javelin|ac|tv_|team|gdrv|npcap|vbox|msio|ctiio|qwen' } | Select-Object Name, State, StartMode, PathName | Format-Table -AutoSize | Out-String -Width 300))

Section '[7] driver files in System32\drivers matching tv|teamviewer|ea|eac|anti|apex|javelin|qwen|gdrv|vbox'
W ((Get-ChildItem 'C:\Windows\System32\drivers' -File | Where-Object { $_.Name -match '(?i)^tv|teamviewer|ea|eac|anti|apex|javelin|qwen|gdrv|vbox' } | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))

Section '[8] System log: SCM failures today'
W ((Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).Date} | Where-Object { $_.Id -in 7000,7001,7009,7011,7023,7024,7026,7031,7034,7045,219 } | Select-Object TimeCreated, Id, ProviderName, @{n='M'; e={$_.Message -replace "`r`n", ' '}} | Format-List | Out-String -Width 400))

Section '[9] System+Application events mentioning anticheat today (full msg)'
W ((Get-WinEvent -FilterHashtable @{LogName='System','Application'; StartTime=(Get-Date).Date} | Where-Object { $_.Message -match '(?i)anticheat|javelin|apexdrv|easyanticheat|EAAntiCheat|QwenKern|gdrv3' } | Select-Object TimeCreated, Id, LogName, ProviderName, @{n='M'; e={$_.Message}} | Format-List | Out-String -Width 400))

Section '[10] bcdedit current (quoted correctly)'
W ((& bcdedit.exe /enum '{current}') | Out-String -Width 300)

Section '[11] DeviceGuard / VBS / HVCI / CI policy'
W ((Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' | Format-List | Out-String -Width 300))
W ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' | Format-List | Out-String))
W ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' | Format-List | Out-String))
W ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Protected' -ErrorAction SilentlyContinue | Format-List | Out-String))
try { W ('SecureBoot: ' + (Confirm-SecureBootUEFI)) } catch { W 'SecureBoot: not available (legacy BIOS?)' }

Section '[12] processes of interest'
W ((Get-Process | Where-Object { $_.ProcessName -match '(?i)eac|anticheat|javelin|apex|teamviewer|origin|^ea' } | Select-Object ProcessName, Id, StartTime, Path | Sort-Object ProcessName | Format-Table -AutoSize | Out-String -Width 300))

Section '[13] services of interest (state)'
W ((Get-Service | Where-Object { $_.Name -match '(?i)ea|javelin|anti|apex|team|tv|vbox|npcap|gdrv' } | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize | Out-String -Width 300))

Section '[14] CodeIntegrity operational events today (full)'
W ((Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 300 | Where-Object { $_.TimeCreated -ge (Get-Date).Date } | Select-Object TimeCreated, Id, LevelDisplayName, @{n='M'; e={$_.Message}} | Format-List | Out-String -Width 400))

Section '[15] Apex game dir listing'
Tree 'C:\Program Files\EA Games\Apex'

Section '[16] __Installer\customcomponent\Javelin'
Tree 'C:\Program Files\EA Games\Apex\__Installer\customcomponent\Javelin'

W ''
W "=== p11 logs done $(Get-Date -Format 'HH:mm:ss') ==="
