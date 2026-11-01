# fix5.ps1 - ELEVATED. Register apexdrv with sc.exe (hand-written keys are not
# seen by the SCM until reboot; ErrorControl= is sc's USAGE trigger, error= is
# correct), then load it and run the kernel probe.
$ErrorActionPreference = 'Continue'
$log = 'C:\qkp\fix5.txt'
function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log }
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'

"== fix5 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
W "lastboot : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
$bcd = (& bcdedit /enum '{current}' 2>&1 | Out-String)
W "testsigning active : $($bcd -match 'testsigning\s+Yes')"
W "drv      : $((Get-Item $drv).Length) B  sig=$((Get-AuthenticodeSignature $drv).Status)"

# --- clear the probe leftovers, then register for real ---
foreach ($n in 'zzprobe', 'kernprobe') { (& sc.exe delete $n) 2>&1 | Out-Null }
(& sc.exe delete apexdrv) 2>&1 | Out-Null
Start-Sleep -Milliseconds 400

# apexdrv was the name used by the failed no-binPath creates; if the SCM still
# has a ghost for it, fall back to a clean name. The device name the launcher
# opens comes from the driver's own CreateDevice, so the SCM name is free.
$svc = $null
foreach ($name in 'apexdrv', 'apexdrv2', 'apexdrvq') {
    W "--- sc.exe create $name (binPath + valid options only) ---"
    (& sc.exe create $name binPath= '\??\C:\Windows\System32\drivers\apexdrv.sys' type= kernel start= demand error= normal) 2>&1 |
        ForEach-Object { W "  create| $_" }
    Start-Sleep -Milliseconds 300
    if ((& sc.exe query $name) 2>&1 | Select-String -SimpleMatch 'SERVICE_NAME') { $svc = $name; break }
    W "  (not visible to the SCM, trying next name)"
}
W "service name chosen : $svc"
if (-not $svc) { W 'FATAL: no name registered'; W 'END'; return }

(& sc.exe qc $svc) 2>&1 | ForEach-Object { W "  qc| $_" }

W "--- sc.exe start $svc ---"
(& sc.exe start $svc) 2>&1 | ForEach-Object { W "  start| $_" }
Start-Sleep -Milliseconds 1500
$st = (Get-Service $svc -ErrorAction SilentlyContinue).Status
W "state    : $st"
W "LOADED   : $($st -eq 'Running')"
W "SERVICE  : $svc"

if ($st -eq 'Running') {
    $b = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
    Set-Location $b
    $apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    W "apex pid : $apex"
    if ($apex) { & .\apex_launcher.exe --kernel-probe --pid=$apex *>&1 | ForEach-Object { W "  probe| $_" } }
    else       { & .\apex_launcher.exe --kernel-probe *>&1 | ForEach-Object { W "  probe| $_" } }
    W "PROBE_EXIT=$LASTEXITCODE"
}

W '--- CodeIntegrity newest 4 ---'
try {
    Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 4 | ForEach-Object {
        W ("  [{0}] id={1}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id)
        W ("    " + (($_.Message -split "`r`n")[0]))
    }
} catch { W "  $($_.Exception.Message)" }
W 'END'
