# h1z - turn the host hypervisor off so the host matches the proven guest config (no VBS / no Secure Kernel).
# VBS Running + the Secure Kernel is why every provider's g_CiOptions store faults (0xBE / 0xC0000005):
# the CiPolicy section stays EPT read-only even with HVCI "Not configured".
# Records the previous setting for restore, then reboots. hypervisorlaunchtype was AUTO before this run.
$o = Join-Path $PSScriptRoot '_h1z.txt'
function W($t){ $t | Add-Content -LiteralPath $o; Write-Host $t }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  exit
}
W ('=== h1z HV OFF ' + (Get-Date -f 'dd/MM/yyyy HH:mm:ss') + ' pid=' + $PID + ' ===')
W ('hv-present=' + (Get-CimInstance Win32_ComputerSystem).HypervisorPresent)
foreach($k in 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard','HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'){
  if(Test-Path $k){ W ('reg ' + $k + ' :: ' + (((Get-ItemProperty $k | Select-Object * -Exclude PS* | Format-List | Out-String) -replace '\s+',' ').Trim())) } else { W ('reg ' + $k + ' :: absent') }
}
W ('bcd-before :: ' + ((bcdedit /enum '{current}' | Select-String 'hypervisorlaunchtype') -join ' '))
& bcdedit /set hypervisorlaunchtype off | ForEach-Object { W ('  ' + $_) }
W ('bcd-after  :: ' + ((bcdedit /enum '{current}' | Select-String 'hypervisorlaunchtype') -join ' '))
W 'rebooting in 15s ...'
W '=== end h1z ==='
& shutdown.exe /r /t 15 /c "h1z: hypervisor off, reboot for DSE retry"
