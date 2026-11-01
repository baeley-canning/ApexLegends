# boot3.ps1 - ELEVATED (SYSTEM), runs 30s after startup on the post-reboot boot.
# Proves test-signing is now ACTIVE, loads apexdrv, and if Apex is up runs the
# kernel reachability probe (Q10).  Self-unregisters.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$st   = 'C:\ProgramData\QwenKern\apexdrv.sys'
$log  = 'C:\qkp\boot3.txt'
function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log }

"== boot3 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
W "lastboot : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
W "elevated : $isAdmin   identity=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

$sg = Get-AuthenticodeSignature $st
W "staged   : $((Get-Item $st -ErrorAction SilentlyContinue).Length) B  sig=$($sg.Status)  signer=$($sg.SignerCertificate.Subject)"

# --- the actual test: does the signed image load NOW that testsigning is live? ---
if (-not (Get-Service apexdrv -ErrorAction SilentlyContinue)) {
    (sc.exe create apexdrv type= kernel start= demand) 2>&1 | ForEach-Object { W "  create| $_" }
} else { W 'service  : already present' }
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv' -Name ImagePath -Value ('\??\' + $st) -Type ExpandString
(& sc.exe start apexdrv) 2>&1 | ForEach-Object { W "  start | $_" }
Start-Sleep -Seconds 1
(& sc.exe query apexdrv) 2>&1 | ForEach-Object { W "  query | $_" }
$loaded = ((Get-Service apexdrv -ErrorAction SilentlyContinue).Status -eq 'Running')
W "LOADED   : $loaded"

if ($loaded) {
    $apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    W "apex pid : $apex"
    Set-Location (Join-Path $root 'build')
    if ($apex) {
        & .\apex_launcher.exe --kernel-probe --driver=$st --pid=$apex *>&1 | ForEach-Object { W "  probe| $_" }
        W "KERNEL_PROBE_EXIT=$LASTEXITCODE"
    } else {
        & .\apex_launcher.exe --kernel-probe --driver=$st *>&1 | ForEach-Object { W "  probe(self)| $_" }
        W "KERNEL_PROBE_EXIT(self)=$LASTEXITCODE"
    }
}

W '--- CodeIntegrity (newest 4) ---'
try {
    Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 4 |
        ForEach-Object { W ("  {0} id={1}" -f $_.TimeCreated.ToString('MM-dd HH:mm:ss'), $_.Id) }
} catch { W "  $($_.Exception.Message)" }

try { Unregister-ScheduledTask -TaskName 'QwenKern-Boot-Load' -Confirm:$false; W 'task     : unregistered' } catch { }
W 'END'
