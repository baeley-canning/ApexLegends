# build\_run_a4_test.ps1
#
# Runs the A4 (thread hijack) rung against a throw-away powershell.exe target and
# writes the launcher's full output plus a completion marker.  Detached so the
# IDE terminal closing cannot kill it mid-run.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\_run_a4_test.ps1 [-Spin] [-Tag name]

param(
    [switch]$Spin,
    [string]$Tag = 'a4_marker'
)

$ErrorActionPreference = 'Continue'
$log  = Join-Path $PSScriptRoot ("phase1_evidence\{0}.txt"  -f $Tag)
$done = Join-Path $PSScriptRoot ("phase1_evidence\{0}.done" -f $Tag)

Remove-Item $done -ErrorAction SilentlyContinue

# -Spin keeps a thread in USER mode (a hijack candidate that is never in a
# kernel wait), which separates "stub is broken" from "thread was in a wait".
$payload = if ($Spin) { 'while($true){}' } else { 'Start-Sleep -Seconds 240' }

$target = Start-Process -FilePath powershell.exe `
    -ArgumentList '-NoProfile', '-Command', $payload `
    -PassThru
Start-Sleep -Milliseconds 900

& (Join-Path $PSScriptRoot 'apex_launcher.exe') --method=hijack --pid $target.Id --inject --no-wait *>&1 |
    Out-File -FilePath $log -Encoding utf8
$code = $LASTEXITCODE

$modules = @()
try {
    $modules = @((Get-Process -Id $target.Id -ErrorAction Stop).Modules |
        Where-Object { $_.ModuleName -like 'apexcheat*' } |
        ForEach-Object { $_.ModuleName })
} catch {
    $modules = @('<target exited>')
}

"exit=$code"            | Out-File -FilePath $done -Encoding ascii
"pid=$($target.Id)"     | Out-File -FilePath $done -Encoding ascii -Append
"modules=$($modules -join ',')" | Out-File -FilePath $done -Encoding ascii -Append

Stop-Process -Id $target.Id -Force -ErrorAction SilentlyContinue

