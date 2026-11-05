# ============================================================================
# build\_verify_testsigning.ps1  - ELEVATED, READ ONLY.
# Confirms the end state after enable_testsigning.ps1 without writing any BCD
# value: test signing, BitLocker protection (recovery-key risk on next boot),
# and the one-shot post-reboot task.
# Output: build\phase1_evidence\_verify_ts.txt
# ============================================================================
[CmdletBinding()]
param([switch] $Elevated)

$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev   = Join-Path $root 'build\phase1_evidence'
$log  = Join-Path $ev '_verify_ts.txt'
if (-not (Test-Path $ev)) { New-Item -ItemType Directory -Path $ev -Force | Out-Null }

function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log; Write-Host $t }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($Elevated) { 'FATAL: not elevated' | Out-File -Encoding utf8 -Append $log; exit 2 }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated') | Out-Null
    Write-Host 'elevated verifier started'
    exit 0
}

"== verify $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') pid=$PID ==" | Out-File -Encoding utf8 -Append $log
W "elevated : True"

foreach ($entry in '{current}', '{bootmgr}') {
    $text = (& cmd /c "bcdedit /enum $entry" 2>&1 | Out-String).Trim()
    W "--- bcdedit /enum $entry EXIT=$LASTEXITCODE ---"
    foreach ($line in ($text -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }
}

$bde = (& manage-bde -status C: 2>&1 | Out-String)
W '--- manage-bde -status C: ---'
foreach ($line in ($bde -split "`r?`n")) { if ($line.Trim()) { W "  $line" } }

$t = Get-ScheduledTask -TaskName 'QwenKern-PostReboot-DriverTest' -ErrorAction SilentlyContinue
W "task registered : $([bool]$t)  state=$($t.State)"
if ($t) {
    W "  action    : $($t.Actions[0].Execute) $($t.Actions[0].Arguments)"
    W "  principal : $($t.Principal.UserId) RunLevel=$($t.Principal.RunLevel)"
    W "  trigger   : $($t.Triggers[0].CimClass.CimClassName) delay=$($t.Triggers[0].Delay)"
}
W 'END'
exit 0
