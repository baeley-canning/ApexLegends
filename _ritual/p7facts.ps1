$ErrorActionPreference = 'SilentlyContinue'
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p7_e.txt'
Remove-Item $o -Force
function W($m) { $m | Out-File $o -Append -Encoding ascii }

W ('== ' + (Get-Date).ToString('HH:mm:ss'))

W '--- windows with titles ---'
Get-Process | Where-Object { $_.MainWindowTitle } |
    Select-Object ProcessName, Id, MainWindowTitle |
    Format-Table -Auto | Out-String -Width 200 | ForEach-Object { W $_ }

W '--- DeviceGuard / VBS ---'
Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard |
    Select-Object VirtualizationBasedSecurityStatus, SecurityServicesConfigured, SecurityServicesRunning |
    Format-List | Out-String | ForEach-Object { W $_ }

W '--- bcdedit {current} ---'
(& bcdedit.exe /enum '{current}') | ForEach-Object { W "  $_" }

W '--- SecureBoot ---'
try { W ('  SecureBoot: ' + (Confirm-SecureBootUEFI)) } catch { W '  SecureBoot: query failed (legacy BIOS?)' }

W '--- HVCI registry ---'
W ('  HVCI Enabled = ' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity').Enabled)
W ('  VBS Enabled  = ' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard').EnableVirtualizationBasedSecurity)

W '--- RUNNING kernel drivers (<= flag) ---'
$known = 'vgk', 'vgc', 'gdrv3', 'gdrv', 'EasyTune', 'iomap64', 'WinRing0x64', 'TeamViewer', 'npcap', 'cpuz',
         'BEDaisy', 'EasyAntiCheat', 'RTCore64', 'sandboxie', 'aswArPot', 'HWiNFO', 'msio', 'inpoutx64', 'WinIo'
Get-CimInstance Win32_SystemDriver | Where-Object { $_.State -eq 'Running' } | ForEach-Object {
    $p = $_.PathName -replace '^\\\?\?\\', '' -replace '^\\SystemRoot\\', 'C:\Windows\'
    $sig = (Get-AuthenticodeSignature $p).SignerCertificate.Subject
    $name = $_.Name
    $sus = if ($known -contains $name) { '<=SUSPECT' } else { '' }
    if (-not $sig) {
        W ('  UNSIGNED | {0} | {1} {2}' -f $name, $p, $sus)
    } elseif ($sig -notmatch 'Microsoft') {
        W ('  {0} | {1} | {2} {3}' -f $name, $p, (($sig -split ',')[0]), $sus)
    }
}

W '--- services of interest ---'
$known | ForEach-Object {
    $svc = Get-Service $_
    if ($svc) { W ('  {0} => {1}  (start={2})' -f $_, $svc.Status, (Get-CimInstance Win32_Service -Filter "Name='$_'").StartMode) }
    else { W ('  {0} => absent' -f $_) }
}

W '--- apexdrv ---'
$sv = Get-Service apexdrv
if ($sv) { W ('  apexdrv => ' + $sv.Status) } else { W '  apexdrv => absent' }

W 'done'
