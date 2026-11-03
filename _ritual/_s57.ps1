$o='C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_s57.txt'
'--- procs ---' | Out-File $o -Encoding ascii
(Get-Process -Name vmmem,vmmemWSL,vmwp,VBoxSVC,VBoxHeadless,docker* -EA 0 | Select-Object Name,Id | Format-Table -AutoSize | Out-String) | Out-File $o -Append -Encoding ascii
'--- deviceguard ---' | Out-File $o -Append -Encoding ascii
(Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -EA 0 | Select-Object VirtualizationBasedSecurityStatus,SecurityServicesConfigured,SecurityServicesRunning,CodeIntegrityPolicyEnforcementStatus | Format-List | Out-String) | Out-File $o -Append -Encoding ascii
'--- hv events ---' | Out-File $o -Append -Encoding ascii
(Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-Hypervisor-Admin' -MaxEvents 15 -EA 0 | Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String -Width 200) | Out-File $o -Append -Encoding ascii
'--- worker events ---' | Out-File $o -Append -Encoding ascii
(Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-Worker-Admin' -MaxEvents 10 -EA 0 | Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String -Width 200) | Out-File $o -Append -Encoding ascii
'--- end ---' | Out-File $o -Append -Encoding ascii
