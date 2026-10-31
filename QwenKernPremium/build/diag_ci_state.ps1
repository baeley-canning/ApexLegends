# ============================================================================
# build\diag_ci_state.ps1  - what does THIS machine accept for a kernel image?
#
# 577 = ERROR_INVALID_IMAGE_HASH: the loader parsed the path (the 123 bug is
# gone) and then refused the *image*.  The decision is made by code integrity,
# so the facts that matter are: Secure Boot, test signing, HVCI/VBS, and which
# of those policies are baked in before boot.  Everything is written to the
# evidence file explicitly, because console capture keeps coming back empty.
#
# Run elevated:  powershell -NoProfile -ExecutionPolicy Bypass -File ...\diag_ci_state.ps1
# ============================================================================
$ErrorActionPreference = 'Continue'
$ev  = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\phase1_evidence'
$log = Join-Path $ev 'ci_state.txt'
function W([string]$t) { $t | Out-File -Encoding utf8 -Append $log }
function C([string]$label, [scriptblock]$sb) {
    try {
        $v = & $sb 2>&1 | Out-String
        W ("{0,-34}: {1}" -f $label, ($v.Trim() -replace "`r`n", ' | '))
    } catch {
        W ("{0,-34}: THREW {1}" -f $label, $_.Exception.Message)
    }
}

"== code-integrity state $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log

# --- who / how --------------------------------------------------------------
W "host    : $env:COMPUTERNAME  user: $env:USERNAME"
W ("elevated: {0}" -f ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
C 'os'            { (Get-CimInstance Win32_OperatingSystem).Caption + ' build ' + (Get-CimInstance Win32_OperatingSystem).BuildNumber }

# --- Secure Boot ------------------------------------------------------------
C 'SecureBoot (cmdlet)'  { Confirm-SecureBootUEFI }
C 'UEFISecureBootEnabled' { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction Stop).UEFISecureBootEnabled }
C 'firmware type'        { $env:firmware_type; (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction SilentlyContinue).PEFirmwareType }

# --- boot policy ------------------------------------------------------------
C 'bcdedit testsigning'  { (bcdedit /enum '{current}' | Select-String -Pattern 'testsigning|nointegritychecks|hypervisorlaunchtype|vsmlaunchtype') -join '; ' }
C 'bcdedit (raw tail)'   { bcdedit /enum '{current}' }

# --- HVCI / VBS -------------------------------------------------------------
C 'DeviceGuard Running'  { (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard).SecurityServicesRunning -join ',' }
C 'DeviceGuard Configured' { (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard).SecurityServicesConfigured -join ',' }
C 'HVCI scenario'        { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue) | Out-String }
C 'VBS status'           { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -ErrorAction SilentlyContinue) | Out-String }

# --- CI protected (what the kernel will enforce at load time) ----------------
C 'CI keys'              { Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\CI' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name }
foreach ($k in 'Protected','Policy','UpgradedSystem') {
    C "CI\$k"            { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI\$k" -ErrorAction SilentlyContinue) | Out-String }
}

# --- the cert the script installs -------------------------------------------
C 'cert ApexDrv Dev'     { Get-ChildItem Cert:\LocalMachine\My, Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
                           Where-Object { $_.Subject -like '*ApexDrv Dev*' } |
                           ForEach-Object { "$($_.PSParentPath.Split('::')[-1]) $($_.Thumbprint) $($_.NotAfter)" } }
C 'cert ApexDrv on image' { (Get-AuthenticodeSignature 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys') |
                           ForEach-Object { "$($_.Status) / $($_.SignerCertificate.Subject)" } }

# --- can the staged image be read at all? ----------------------------------
C 'staged image'         { Get-Item 'C:\ProgramData\QwenKern\apexdrv.sys' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName) $($_.Length) bytes" } }
C 'staged signature'     { (Get-AuthenticodeSignature 'C:\ProgramData\QwenKern\apexdrv.sys' -ErrorAction SilentlyContinue) |
                           ForEach-Object { "$($_.Status) / $($_.SignerCertificate.Subject)" } }

# --- last kernel load failures in the event log -----------------------------
C 'CodeIntegrity log'    { Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 12 -ErrorAction SilentlyContinue |
                           ForEach-Object { $_.TimeCreated.ToString('MM-dd HH:mm:ss') + ' ' + $_.Id + ' ' + (($_.Message -split "`r`n")[0]) } }
C 'System 7045/7000'     { Get-WinEvent -FilterHashtable @{LogName='System'; Id=7045,7000,7026,219} -MaxEvents 10 -ErrorAction SilentlyContinue |
                           ForEach-Object { $_.TimeCreated.ToString('MM-dd HH:mm:ss') + ' ' + $_.Id + ' ' + (($_.Message -split "`r`n")[0]) } }

'DIAG_CI_STATE_DONE' | Out-File -Encoding utf8 -Append $log
