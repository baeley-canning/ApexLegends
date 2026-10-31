# build\_run_ladder_test.ps1
#
# Runs the full usermode ladder (A8 SKIP -> A7 -> A4 -> A3 -> A2 -> A1 -> B3)
# against a throw-away powershell.exe target, with a fresh sticky file, and
# records: launcher output, exit code, payload presence in the module list, and
# the sticky file the ladder wrote.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\_run_ladder_test.ps1 [-Tag name] [-Spin]

param(
    [string]$Tag = 'ladder',
    [switch]$Spin
)

$ErrorActionPreference = 'Continue'
$evidence = Join-Path $PSScriptRoot 'phase1_evidence'
$log  = Join-Path $evidence ("{0}.txt"  -f $Tag)
$done = Join-Path $evidence ("{0}.done" -f $Tag)
$sticky = Join-Path $PSScriptRoot 'apexcheat.launcher.ini'

New-Item -ItemType Directory -Force -Path $evidence | Out-Null
Remove-Item $done -ErrorAction SilentlyContinue
Remove-Item $sticky -ErrorAction SilentlyContinue

$payload = if ($Spin) { 'while($true){}' } else { 'Start-Sleep -Seconds 240' }

$target = Start-Process -FilePath powershell.exe `
    -ArgumentList '-NoProfile', '-Command', $payload `
    -PassThru
Start-Sleep -Milliseconds 900

& (Join-Path $PSScriptRoot 'apex_launcher.exe') --forget-sticky --inject --pid $target.Id --no-wait *>&1 |
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

$stickyText = if (Test-Path $sticky) { (Get-Content $sticky) -join ' | ' } else { '<no sticky file>' }

"exit=$code"                     | Out-File -FilePath $done -Encoding ascii
"pid=$($target.Id)"              | Out-File -FilePath $done -Encoding ascii -Append
"modules=$($modules -join ',')"   | Out-File -FilePath $done -Encoding ascii -Append
"sticky=$stickyText"             | Out-File -FilePath $done -Encoding ascii -Append

Stop-Process -Id $target.Id -Force -ErrorAction SilentlyContinue
