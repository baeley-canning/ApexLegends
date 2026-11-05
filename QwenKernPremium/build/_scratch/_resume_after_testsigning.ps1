# ============================================================================
# build\_resume_after_testsigning.ps1  - ELEVATED, runs 30s after logon once the
# test-signing reboot has happened (registered by enable_testsigning.ps1).
#
# It is deliberately dumb and ordered:
#   1. prove test signing survived the reboot (that is the whole point)
#   2. remove the stale System32\drivers\apexdrv.sys copy, which is what the
#      old service ImagePath pointed at (11:52:55 timestamp, pre-dates the
#      ProgramData stage)
#   3. run build\sign_and_test_driver.ps1 unchanged - it rebuilds+gate, signs,
#      stages to C:\ProgramData\QwenKern, loads, measures, tears down, and
#      writes build\phase1_evidence\driver_done.txt
#   4. report whether the image actually loaded, and unregister itself
#
# Results: build\phase1_evidence\post_reboot.txt
# ============================================================================
$ErrorActionPreference = 'Continue'

$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev   = Join-Path $root 'build\phase1_evidence'
$log  = Join-Path $ev 'post_reboot.txt'
$task = 'QwenKern-PostReboot-DriverTest'

function W([string] $t) {
    $t | Out-File -Encoding utf8 -Append $log
    Write-Host $t
}

"== post-reboot driver test $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
W "elevated : $isAdmin  (task principal should make this True)"
W "boot     : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"

# --- 1: did the policy survive the reboot? ----------------------------------
# cmd.exe keeps the braces away from PowerShell 5.1's argument rewriter.
$bcd = (& cmd /c 'bcdedit /enum {current}' 2>&1 | Out-String).Trim()
W "--- bcdedit /enum {current} EXIT=$LASTEXITCODE ---"
foreach ($line in ($bcd -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
$testsigning = $bcd -match 'testsigning\s+Yes'
W "testsigning : $testsigning"
if (-not $testsigning) {
    W 'FAILED: test signing is off again - the BCD write did not stick. Retry the enabler.'
    'POST_REBOOT_FAILED(no-testsigning)' | Out-File -Encoding utf8 (Join-Path $ev 'driver_done.txt')
    # self-clean: this may have fired before the enabler ever succeeded, and a
    # task that keeps firing on every logon would recreate/delete the service
    # under whatever runs next.
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false
        W "task     : '$task' unregistered (it fired while testsigning was off, so the test was not run)"
    }
    exit 1
}

# --- 2: the stale System32 copy --------------------------------------------
$stale = 'C:\Windows\System32\drivers\apexdrv.sys'
if (Test-Path $stale) {
    $fi = Get-Item $stale
    W "stale    : $stale  $($fi.Length) bytes  $($fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    try {
        Remove-Item $stale -Force -ErrorAction Stop
        W 'stale    : removed (the service will point at C:\ProgramData\QwenKern\apexdrv.sys)'
    } catch {
        W "stale    : could not remove - $($_.Exception.Message)"
    }
} else {
    W "stale    : none at $stale"
}

# --- 3: the real test ------------------------------------------------------
W '--- running build\sign_and_test_driver.ps1 ---'
Set-Location $root
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'build\sign_and_test_driver.ps1') *>&1 |
    Out-File -Encoding utf8 (Join-Path $ev 'post_reboot_driver_console.txt')
$driverExit = $LASTEXITCODE
W "driver   : EXIT=$driverExit"

# --- 4: verdict ------------------------------------------------------------
$loadLog = Join-Path $ev 'driver_sign_load.txt'
$tail    = if (Test-Path $loadLog) { Get-Content $loadLog } else { @() }
$loadedLines = $tail | Select-String -Pattern 'loaded\s*:' | Select-Object -Last 1
$loaded = $loadedLines -and ($loadedLines.Line -match 'loaded\s*:\s*True')
W "load log : $(Join-Path $ev 'driver_sign_load.txt') -> '$($loadedLines.Line)'"

$probe = Join-Path $ev 'kernel_probe.txt'
if (Test-Path $probe) {
    $probeExit = (Get-Content $probe | Select-String -Pattern 'KERNEL_PROBE_EXIT=' | Select-Object -Last 1).Line
    W "probe    : $probeExit"
    foreach ($line in (Get-Content $probe | Select-Object -First 25)) { if ($line.Trim()) { W "  | $line" } }
}

if (-not $loaded) {
    W '--- last CodeIntegrity events (why did it not load?) ---'
    try {
        Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 10 -ErrorAction Stop |
            ForEach-Object { W ("  {0} id={1} {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm:ss'), $_.Id, (($_.Message -split "`r`n")[0])) }
    } catch {
        W "  CodeIntegrity log: $($_.Exception.Message)"
    }
    W '--- sc query apexdrv / sc qc apexdrv ---'
    (& sc.exe query apexdrv 2>&1) | ForEach-Object { if ("$_".Trim()) { W "  $_" } }
    (& sc.exe qc apexdrv 2>&1)    | ForEach-Object { if ("$_".Trim()) { W "  $_" } }
}

# The gate has to pass on the same tree that just proved the driver loads.
W '--- re-running tools\BuildGate.ps1 ---'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\BuildGate.ps1') *>&1 |
    Out-File -Encoding utf8 (Join-Path $ev 'gate_after_driver.txt')
$gateExit = $LASTEXITCODE
W "gate     : EXIT=$gateExit  ($(Join-Path $ev 'gate_after_driver.txt'))"

if ($loaded -and $gateExit -eq 0) {
    W 'RESULT: OK - apexdrv loaded under test signing and the gate passes.'
    'POST_REBOOT_OK' | Out-File -Encoding utf8 (Join-Path $ev 'driver_done.txt')
    $result = 0
} else {
    W "RESULT: FAILED - driverExit=$driverExit loaded=$loaded gateExit=$gateExit"
    "POST_REBOOT_FAILED(loaded=$loaded gate=$gateExit)" | Out-File -Encoding utf8 (Join-Path $ev 'driver_done.txt')
    $result = 1
}

# One shot: this task has done its job.  Leaving it registered would re-run the
# test on every logon and recreate/delete the service under whatever comes next.
if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $task -Confirm:$false
    W "task     : '$task' unregistered"
}
W 'END'
exit $result

