$ErrorActionPreference = 'SilentlyContinue'
$root = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out  = Join-Path $root 'p12_env.txt'
function W { param([string]$t) $t | Out-File -FilePath $out -Append -Encoding utf8 }
function Sec { param([string]$t) W ''; W ('########## ' + $t + ' ##########') }
"=== p12 env snapshot $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $out -Encoding utf8

$d = 'C:\Windows\System32\drivers'
Sec '[1] drivers dir: 35 newest *.sys (spot third-party)'
W ((Get-ChildItem $d -Filter *.sys -Force -File | Sort-Object LastWriteTime -Descending | Select-Object -First 35 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))
Sec '[2] drivers dir: name match anticheat|ea$|apex|cea|stream|npcap|gdrv|vbox|skyfall'
W ((Get-ChildItem $d -Force -File | Where-Object { $_.Name -match '(?i)anticheat|^ea|apex|cea|stream|npcap|gdrv|vbox|skyfall' } | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))
Sec '[3] suspect driver identity + signature + whether service points at it'
foreach ($n in @('CEA.sys','stream.sys','PEAuth.sys','apexdrv.sys','eaanticheat.sys','gdrv3.sys','VBoxDrv.sys','npcap.sys')) {
  $p = Join-Path $d $n
  if (Test-Path -LiteralPath $p) {
    $vi = (Get-Item -LiteralPath $p).VersionInfo
    $sg = (Get-AuthenticodeSignature -LiteralPath $p)
    W ("$n  | company=$($vi.CompanyName) | desc=$($vi.FileDescription) | ver=$($vi.FileVersion) | sig=$($sg.Status) | signer=$($sg.SignerCertificate.Subject)")
  } else { W "$n : ABSENT" }
}
Sec '[4] Win32_SystemDriver relevant (state/path)'
W ((Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match '(?i)anticheat|apexdrv|zzprobe|cea|stream|vbox|gdrv|teamviewer|npcap|qwen|skyfall' } | Select-Object Name,State,StartMode,PathName | Sort-Object Name | Format-Table -AutoSize | Out-String -Width 300))
Sec '[5] services matching anticheat|apexdrv|zzprobe|skyfall|javelin (reg)'
W ((Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object { $_.PSChildName -match '(?i)anticheat|apexdrv|zzprobe|skyfall|javelin|cea' } | ForEach-Object { $p = Get-ItemProperty $_.PSPath; $_.PSChildName + ' | Type=' + $p.Type + ' | Start=' + $p.Start + ' | ImagePath=' + $p.ImagePath }) | Out-String)
Sec '[6] bcdedit current + full'
W ((cmd /c 'bcdedit /enum {current}') | Out-String -Width 300)
W ((cmd /c 'bcdedit /enum') | Out-String -Width 300)
Sec '[7] DeviceGuard / VBS / CI policy state'
W ((Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard | Select-Object * | Format-List | Out-String))
W ((reg query 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' /s) | Out-String)
W ((reg query 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy' /s) | Out-String)
Sec '[8] fltmc filters (loaded minifilters)'
W ((cmd /c 'fltmc filters') | Out-String -Width 300)
Sec '[9] DriverStore / packages matching anticheat|javelin|skyfall'
W ((Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Directory -Force | Where-Object { $_.Name -match '(?i)anticheat|javelin|skyfall' } | Select-Object -ExpandProperty Name | Out-String))
W ((Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Recurse -Force -File -Filter '*.sys' -Depth 2 | Where-Object { $_.Name -match '(?i)anticheat|skyfall|javelin' } | Select-Object FullName,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 300))

Sec '[10] AC log / artefact hunt (recent)'
$cut = (Get-Date).AddDays(-30)
$roots = @('C:\ProgramData', 'C:\Program Files\EA\AC', 'C:\Program Files\EA Games\Apex', (Join-Path $env:LOCALAPPDATA 'CrashDumps'), $env:LOCALAPPDATA, $env:APPDATA, $env:TEMP, 'C:\Windows\Temp')
foreach ($r in $roots) {
  if (-not (Test-Path -LiteralPath $r)) { W ('MISSING ' + $r); continue }
  W ('---- ' + $r + ' ----')
  W ((Get-ChildItem -LiteralPath $r -Recurse -Force -File -Depth 4 | Where-Object { $_.LastWriteTime -ge $cut -and ($_.Name -match '(?i)javelin|anticheat|anti.?cheat|skyfall|game.?service|\.dmp$|\.log$') } | Sort-Object LastWriteTime -Descending | Select-Object -First 60 FullName,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 400))
}
Sec '[11] WER reports mentioning EAAntiCheat / skyfall / GameService'
foreach ($r in @('C:\ProgramData\Microsoft\Windows\WER\ReportArchive', 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue', (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'))) { if (-not (Test-Path -LiteralPath $r)) { W ('MISSING ' + $r); continue }; W ('---- ' + $r + ' ----'); W ((Get-ChildItem -LiteralPath $r -Force | Where-Object { $_.Name -match '(?i)anticheat|skyfall|gameservice|jav' } | Sort-Object LastWriteTime -Descending | Select-Object -First 20 Name,LastWriteTime | Format-Table -AutoSize | Out-String -Width 300)) }
Sec '[12] any file under C:\ProgramData modified in last 3 days (top 80)'
W ((Get-ChildItem 'C:\ProgramData' -Recurse -Force -File -Depth 5 | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-3) } | Sort-Object LastWriteTime -Descending | Select-Object -First 80 FullName,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 400))
Sec '[13] apexdrv.sys bytes + sig (our test driver, if present)'
$ap = Join-Path $d 'apexdrv.sys'
if (Test-Path -LiteralPath $ap) { W ((Get-AuthenticodeSignature -LiteralPath $ap | Format-List | Out-String)); W ((Get-ChildItem -LiteralPath $ap | Format-List Name,Length,CreationTime,LastWriteTime | Out-String)) } else { W 'apexdrv.sys ABSENT from drivers dir' }
W ''
W "=== p12 env DONE $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
