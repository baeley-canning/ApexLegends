# _d3.ps1 - pinpoint the exact blocking call in p36's environment block.
# Writes a marker BEFORE and AFTER every risky call, so the last "enter" with no
# matching "ok" is the hang.  Add-Content (immediate) + Write-Host (to test the
# second suspect: a blocked console/stdout).
$b = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$D = "$b\_d3.txt"
function W([string]$s) { Add-Content -LiteralPath $D -Value ((Get-Date -f 'HH:mm:ss.fff') + '  ' + $s) -Encoding ascii }
function Mark([string]$s) { W ("ENTER $s"); Write-Host $s; W ("ok    $s") }
Set-Content -LiteralPath $D -Value ('=== d3 ' + (Get-Date -f 'dd/MM/yyyy HH:mm:ss') + ' pid=' + $PID + ' ===') -Encoding ascii
W 'START'
W ('admin=' + [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))

Mark 'S2 CIM Win32_OperatingSystem (p36 line42)'
try { $os = Get-CimInstance Win32_OperatingSystem -EA 0; W ('  os=' + $os.Caption + ' build=' + $os.BuildNumber) } catch { W ('  os EXC ' + $_.Exception.Message) }

Mark 'S3 CIM Win32_Processor (p36 line43)'
try { $cpu = Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1; W ('  cpu=' + $cpu.Name) } catch { W ('  cpu EXC ' + $_.Exception.Message) }

Mark 'S4 Get-ItemProperty SecureBoot (p36 line45)'
try { $sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -EA 0).UEFISecureBootEnabled; W ('  secureboot=' + $sb) } catch { W ('  sb EXC ' + $_.Exception.Message) }

Mark 'S5 Get-ItemProperty SystemStartOptions (p36 line47)'
try { $sso = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -EA 0).SystemStartOptions; W ('  sysstart=[' + $sso + ']') } catch { W ('  sso EXC ' + $_.Exception.Message) }

Mark 'S6 bcdedit.exe (p36 line49)'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try { $raw = (& bcdedit.exe /enum '{current}' 2>&1); W ('  bcdedit_ms=' + $sw.ElapsedMilliseconds + ' lines=' + @($raw).Count) } catch { W ('  bcd EXC ' + $_.Exception.Message) }

Mark 'S7 CIM Win32_DeviceGuard NO timeout (p36 line52)'
$sw.Restart()
try { $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -EA 0; W ('  devguard_ms=' + $sw.ElapsedMilliseconds + ' ok=' + [bool]$dg) } catch { W ('  dg EXC ' + $_.Exception.Message) }

Mark 'S8 sc.exe query x5 (p36 line56)'
foreach ($s in 'gdrv3', 'MsIo', 'apexdrv', 'eaanticheat', 'EAAntiCheatService') {
    $sw.Restart()
    try { $r = ((& sc.exe query $s 2>&1) -join ' '); W ('  sc ' + $s + ' ms=' + $sw.ElapsedMilliseconds + ' found=' + [bool]($r -match 'SERVICE_NAME')) } catch { W ('  sc ' + $s + ' EXC ' + $_.Exception.Message) }
}
Mark 'S9 END'
