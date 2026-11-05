# build\_run_live_probe.ps1
#
# Measures the LIVE game (r5apex_dx12.exe) with the AG harness only - never
# injects.  Must run ELEVATED, otherwise X1 (OpenProcess) fails with win32 5 and
# every later probe is unanswerable.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\_run_live_probe.ps1 [-Tag name]
#
# Writes build\phase1_evidence\<Tag>.txt (launcher output) and <Tag>.done
# (exit code, pid, elevation, module-count sanity check).

param(
    [string]$Tag = 'live_probe'
)

$ErrorActionPreference = 'Continue'
$evidence = Join-Path $PSScriptRoot 'phase1_evidence'
$log  = Join-Path $evidence ("{0}.txt"  -f $Tag)
$done = Join-Path $evidence ("{0}.done" -f $Tag)

New-Item -ItemType Directory -Force -Path $evidence | Out-Null
Remove-Item $done -ErrorAction SilentlyContinue
Remove-Item $log  -ErrorAction SilentlyContinue

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

$game = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) {
    "exit=-1"            | Out-File -FilePath $done -Encoding ascii
    "reason=no game pid" | Out-File -FilePath $done -Encoding ascii -Append
    "elevated=$elevated"| Out-File -FilePath $done -Encoding ascii -Append
    exit 1
}

Push-Location $PSScriptRoot

& .\apex_launcher.exe --probe --pid $game.Id --no-wait *>&1 |
    Out-File -FilePath $log -Encoding utf8
$code = $LASTEXITCODE

# Independent cross-check of the "module list unreadable" symptom, from a
# different API than the launcher's (per the X8 entry in the measurement doc).
$modules = 'unknown'
try {
    $modules = @((Get-Process -Id $game.Id -ErrorAction Stop).Modules).Count
} catch {
    $modules = "<exception: $($_.Exception.Message)>"
}

$sticky = Join-Path $PSScriptRoot 'apexcheat.launcher.ini'
$stickyText = if (Test-Path $sticky) { (Get-Content $sticky) -join ' | ' } else { '<no sticky file>' }

Pop-Location

"exit=$code"            | Out-File -FilePath $done -Encoding ascii
"pid=$($game.Id)"       | Out-File -FilePath $done -Encoding ascii -Append
"elevated=$elevated"   | Out-File -FilePath $done -Encoding ascii -Append
"ps_modules=$modules"   | Out-File -FilePath $done -Encoding ascii -Append
"sticky=$stickyText"    | Out-File -FilePath $done -Encoding ascii -Append
