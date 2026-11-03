# vm_gate1_probe.ps1 - GUEST side, read-only state probe before the VM GATE.
# Runs as vboxuser (possibly non-elevated): nothing here mutates the guest.
$o = 'C:\Users\vboxuser\vm_gate1_probe.txt'
function W($s) { $s | Out-File -FilePath $o -Encoding utf8 -Append }
if (Test-Path $o) { Remove-Item $o -Force }

W ('=== vm_gate1 probe ' + (Get-Date) + ' ===')
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
W ('user: ' + $id.Name + ' | isAdmin: ' + $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
try { W ('UAC EnableLUA: ' + (Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -EA Stop)) } catch { W ('UAC EnableLUA ERR: ' + $_.Exception.Message) }
$os = Get-CimInstance Win32_OperatingSystem
W ('os: ' + $os.Caption + ' build ' + $os.BuildNumber)
W ('host: ' + $env:COMPUTERNAME)

W '--- bcdedit flags (may need admin) ---'
try { W ((bcdedit /enum '{current}' 2>&1 | Select-String -Pattern 'testsigning|nointegritychecks|hypervisorlaunchtype' | Out-String)) } catch { W ('bcdedit ERR: ' + $_.Exception.Message) }
try { W ('SystemStartOptions: ' + (Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -EA Stop)) } catch { W 'SystemStartOptions ERR' }

W '--- testsigning effective (CI) ---'
try { W ('TestSigningAllowed: ' + (Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\State' -Name TestSigningAllowed -EA SilentlyContinue)) } catch { W 'TestSigningAllowed key absent (normal when off)' }

W '--- Apex install ---'
foreach ($p in @('C:\Program Files\EA Games\Apex\r5apex_dx12.exe', 'C:\Program Files\EA Games\Apex', 'C:\Program Files\EA\AC\EAAntiCheat.GameService.exe')) {
  W ('' + $p + ' exists=' + (Test-Path $p))
}

W '--- running game/AC processes ---'
W ((Get-Process | Where-Object { $_.Name -match 'r5apex|EAAntiCheat|EADesktop|EasyAntiCheat' } | Select-Object Id, Name, StartTime | Format-Table -AutoSize | Out-String -Width 200))

W '--- services ---'
foreach ($s in @('apexdrv', 'EAAntiCheat', 'EAAntiCheatService')) {
  W ('--- sc query ' + $s)
  W ((cmd /c "sc query $s 2>&1" | Out-String))
  W ((cmd /c "sc qc $s 2>&1" | Out-String))
}

W '--- staged dirs ---'
foreach ($p in @('C:\Users\vboxuser\qkp', 'C:\ProgramData\QwenKern', 'C:\Users\vboxuser')) {
  if (Test-Path $p) {
    W ('---- ' + $p)
    W ((Get-ChildItem $p -File -EA 0 | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 200))
  } else { W ('MISSING ' + $p) }
}

W '--- display adapter + 3D ---'
W ((Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, VideoModeDescription | Format-List | Out-String))

W ('--- free space: ' + (Get-PSDrive C | ForEach-Object { $_.Free }))

W '--- recent bugchecks (24h) ---'
try { W ((Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; StartTime=(Get-Date).AddDays(-1)} -EA 0 | Select-Object -First 5 TimeCreated, Message | Format-List | Out-String)) } catch { W 'none' }

W ('=== DONE ' + (Get-Date) + ' ===')
