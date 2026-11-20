param([switch]$ElevatedChild)
$ErrorActionPreference = 'Continue'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_boot_out.txt"
$r = @()
$r += 'sb=' + (try { (Confirm-SecureBootUEFI).ToString() } catch { 'ERR:' + $_.Exception.Message })
$r += 'fw=' + (try { (Get-ComputerInfo -Property BiosFirmwareType).BiosFirmwareType } catch { 'na' })
$r += 'ci_testsign=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI' -Name TestSigning -ErrorAction SilentlyContinue).TestSigning
$b = bcdedit /enum '{current}' 2>&1 | Out-String
$r += 'bcd_testsign=' + ([regex]::Match($b, '(?m)^testsigning\s+(\S+)').Groups[1].Value)
$r += 'bcd_nointegrity=' + ([regex]::Match($b, '(?m)^nointegritychecks\s+(\S+)').Groups[1].Value)
$r += 'bcd_hv=' + ([regex]::Match($b, '(?m)^hypervisorlaunchtype\s+(\S+)').Groups[1].Value)
$r += 'mssec=' + (Get-MpComputerStatus -ErrorAction SilentlyContinue).IsTamperProtected
$r += 'vbs=' + (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue).VirtualizationBasedSecurityStatus
$r | Out-File -LiteralPath $out -Encoding ascii
