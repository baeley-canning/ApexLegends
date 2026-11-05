# ============================================================================
# build\enable_testsigning.ps1  - ELEVATED: turn on boot test signing, then arm
# a one-shot task that re-runs the driver test after the reboot.
#
# Why this is the right lever (see build\phase1_evidence\*):
#   * Secure Boot is ON, VBS/HVCI is OFF  -> test signing is permitted.
#   * The driver is signed with a self-signed cert that IS in Root +
#     TrustedPublisher, yet CI still answers 0xC0000428 (577
#     ERROR_INVALID_IMAGE_HASH) with event 3004: a self-signed leaf is only
#     accepted by the kernel loader when testsigning is enabled (it is a
#     "beta/test" image, not a WHQL one).
#
# Notes learned the hard way:
#   * bcdedit cannot even OPEN the store unelevated here: "Access is denied",
#     and the brace form then reports "The specified entry type is invalid".
#     Every bcdedit call below therefore goes through cmd.exe, elevated.
#   * A BCD change moves the PCR-11 measurement, so if BitLocker protection is
#     ON the next boot can ask for the recovery key.  The state and the
#     protectors are dumped to the evidence file before anything is written.
#
# Run (self-elevates):
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\enable_testsigning.ps1
# Results: build\phase1_evidence\testsigning.txt
# ============================================================================
[CmdletBinding()]
param([switch] $Elevated)

$ErrorActionPreference = 'Continue'

$root   = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev     = Join-Path $root 'build\phase1_evidence'
$log    = Join-Path $ev 'testsigning.txt'
$task   = 'QwenKern-PostReboot-DriverTest'
$resume = Join-Path $root 'build\_resume_after_testsigning.ps1'

if (-not (Test-Path $ev)) { New-Item -ItemType Directory -Path $ev -Force | Out-Null }

function W([string] $t) {
    $line = $t
    $line | Out-File -Encoding utf8 -Append $log
    Write-Host $line
}

# Every bcdedit call: cmd.exe keeps the {current} braces away from PowerShell
# 5.1 (which otherwise rewrites the line as -encodedCommand), and $LASTEXITCODE
# is bcdedit's own exit code because cmd forwards it.
function Bcd([string] $arguments) {
    $text = (& cmd /c "bcdedit $arguments" 2>&1 | Out-String).Trim()
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = $text }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

"== enable test signing $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
W "user     : $env:USERDOMAIN\$env:USERNAME on $env:COMPUTERNAME"
W "elevated : $isAdmin"

if (-not $isAdmin) {
    if ($Elevated) {
        W 'FATAL: still not elevated after the UAC prompt was accepted - aborting'
        exit 2
    }
    W 'relaunching elevated (accept the UAC prompt)...'
    $reArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $reArgs | Out-Null
        Write-Host 'elevated instance started - progress is in build\phase1_evidence\testsigning.txt'
        exit 0
    } catch {
        W "FATAL: elevation refused: $($_.Exception.Message)"
        exit 2
    }
# --- 1: policy context ------------------------------------------------------
$sb = '?'
try { $sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction Stop).UEFISecureBootEnabled } catch { }
W "SecureBoot               : $sb  (1 = on)"
$vbs = '?'
try { $vbs = (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop).SecurityServicesRunning -join ',' } catch { }
W "VBS/HVCI services running: '$vbs'  (empty or 0 = HVCI off, test signing allowed)"
$hvci = '?'
try { $hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue).Enabled } catch { }
W "HVCI scenario Enabled    : $hvci"

# --- 2: BitLocker (a BCD write changes the PCR-11 measurement) --------------
$bde = (& manage-bde -status C: 2>&1 | Out-String)
W '--- manage-bde -status C: ---'
foreach ($line in ($bde -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
$protectionOn = $bde -match 'Protection Status:\s*Protection On'
W "BitLocker protection ON  : $protectionOn"
if ($protectionOn) {
    $prot = (& manage-bde -protectors -get C: 2>&1 | Out-String)
    W '--- manage-bde -protectors -get C:  (SAVE THE RECOVERY KEY FROM HERE) ---'
    foreach ($line in ($prot -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
    W 'WARN: protection is on - the next boot may ask for the recovery key above.'
}

# --- 3: current boot policy -------------------------------------------------
$before = Bcd '/enum {current}'
W "--- bcdedit /enum {current} (before) EXIT=$($before.Exit) ---"
foreach ($line in ($before.Text -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
$alreadyOn = $before.Text -match 'testsigning\s+Yes'
W "testsigning already on   : $alreadyOn"

# --- 4: turn it on ----------------------------------------------------------
if ($alreadyOn) {
    W 'nothing to write - test signing is already enabled'
} else {
    $set = Bcd '/set testsigning on'
    W "--- bcdedit /set testsigning on EXIT=$($set.Exit) ---"
    foreach ($line in ($set.Text -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
    if ($set.Text -match 'Secure Boot policy|protected') {
        W 'BLOCKED: the stored value is protected by Secure Boot policy ->'
        W '         disable Secure Boot in firmware setup, then run this script again.'
    }
}

# --- 5: verify --------------------------------------------------------------
$after = Bcd '/enum {current}'
W "--- bcdedit /enum {current} (after) EXIT=$($after.Exit) ---"
foreach ($line in ($after.Text -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
$nowOn = $after.Text -match 'testsigning\s+Yes'
W "testsigning now on       : $nowOn"

if (-not $nowOn) {
    W 'RESULT: FAILED - test signing is still off; nothing was armed for reboot'
    exit 1
}

}

# --- 6: arm the post-reboot run (one shot, highest privileges) --------------
# The reboot is the only way the loader sees the new policy, so the re-test has
# to happen after it.  A task is used instead of "run it by hand later" because
# the hand step has been the thing that keeps slipping.
if (-not (Test-Path $resume)) {
    W "RESULT: FAILED - resume script missing: $resume"
    exit 1
}
if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $task -Confirm:$false
    W "task     : removed the previous '$task'"
}
$user = "$env:USERDOMAIN\$env:USERNAME"
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$resume`"" `
    -WorkingDirectory $root
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT30S'
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'One shot: after the test-signing reboot, sign+load apexdrv, re-run the gate.' | Out-Null
$registered = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
W "task     : '$task' registered=$([bool]$registered) state=$($registered.State)"
W "resume   : $resume"
W ''
W 'RESULT: OK - test signing is ON.  REBOOT now; the task re-runs the driver test 30s after logon.'
W '        (manual equivalent: powershell -File build\_resume_after_testsigning.ps1)'
W 'END'
exit 0

