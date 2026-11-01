# fix4.ps1 - ELEVATED. Creates the apexdrv kernel service directly in the
# registry (sc.exe create was failing 487), stages the SIGNED driver into the
# canonical System32\drivers path and loads it.
$ErrorActionPreference = 'Continue'
$log = 'C:\qkp\fix4.txt'
function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log }

"== fix4 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
W "elevated : $isAdmin"
W "lastboot : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
$bcd = (& cmd /c 'bcdedit /enum {current}' 2>&1 | Out-String)
W "bcd testsigning=Yes : $($bcd -match 'testsigning\s+Yes')"
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
W "VBS status=$($dg.VirtualizationBasedSecurityStatus) servicesRunning=$($dg.SecurityServicesRunning -join ',')  (0 = HVCI off)"

# --- what -- if anything -- is wedged in the service key right now ---
$key = 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv'
if (Test-Path $key) {
    W 'regkey : PRE-EXISTING (this is why sc create 487s)'
    (Get-ItemProperty $key) | Format-List * | Out-String -Stream |
        Where-Object { $_.Trim() } | ForEach-Object { W "  pre| $_" }
} else { W 'regkey : absent' }

# --- stage the SIGNED driver in the canonical location ---
$src = 'C:\ProgramData\QwenKern\apexdrv.sys'
$dst = 'C:\Windows\System32\drivers\apexdrv.sys'
Copy-Item $src $dst -Force
W "copy   : $dst  $((Get-Item $dst).Length) B  sig=$((Get-AuthenticodeSignature $dst).Status)"
W "srcsig : $((Get-AuthenticodeSignature $src).Status)  signer=$((Get-AuthenticodeSignature $src).SignerCertificate.Subject)"

# --- (re)create the kernel service via the registry: no sc.exe needed ---
Remove-Item $key -Force -ErrorAction SilentlyContinue
New-Item -Path $key -Force | Out-Null
Set-ItemProperty $key -Name 'Type'         -Value 1 -Type DWord            # 1 = kernel driver
Set-ItemProperty $key -Name 'Start'        -Value 3 -Type DWord            # 3 = demand
Set-ItemProperty $key -Name 'ErrorControl' -Value 1 -Type DWord
Set-ItemProperty $key -Name 'ImagePath'    -Value 'System32\drivers\apexdrv.sys' -Type ExpandString
Set-ItemProperty $key -Name 'ObjectName'   -Value 'LocalSystem' -Type String
Set-ItemProperty $key -Name 'DisplayName'  -Value 'Apex kernel bridge (QwenKern)' -Type String
W 'service: key written directly (Type=1 kernel, Start=3 demand, ImagePath=System32\drivers\apexdrv.sys)'

# --- the moment of truth ---
(& sc.exe start apexdrv) 2>&1 | ForEach-Object { W "  start| $_" }
Start-Sleep -Milliseconds 1200
(& sc.exe query apexdrv) 2>&1 | ForEach-Object { W "  query| $_" }
$loaded = ((Get-Service apexdrv -ErrorAction SilentlyContinue).Status -eq 'Running')
W "LOADED   : $loaded"

# --- if it is in: probe the driver, and the game if it is up ---
if ($loaded) {
    Set-Location 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
    $apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    W "apex pid : $apex"
    if ($apex) {
        & .\apex_launcher.exe --kernel-probe --driver=$dst --pid=$apex *>&1 | ForEach-Object { W "  probe| $_" }
    } else {
        & .\apex_launcher.exe --kernel-probe --driver=$dst *>&1 | ForEach-Object { W "  probe| $_" }
    }
    W "PROBE_EXIT=$LASTEXITCODE"
}

W '--- CodeIntegrity newest 6 (full first line) ---'
try {
    Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 6 | ForEach-Object {
        W ("  [{0}] id={1}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id)
        W ("    " + (($_.Message -split "`r`n")[0]))
    }
} catch { W "  $($_.Exception.Message)" }
W 'END'
