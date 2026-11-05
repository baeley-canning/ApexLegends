# build\_run_live_ladder.ps1
#
# Runs the REAL injection ladder against the live r5apex_dx12.exe (ELEVATED).
# Records the ladder transcript plus, afterwards, whether apexcheat.dll actually
# landed in the target's module list.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\_run_live_ladder.ps1 [-Tag name]

param(
    [string]$Tag = 'live_ladder'
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
    "exit=-1`nreason=no game pid`nelevated=$elevated" | Out-File -FilePath $done -Encoding ascii
    exit 1
}

Push-Location $PSScriptRoot

& .\apex_launcher.exe --inject --pid $game.Id *>&1 | Out-File -FilePath $log -Encoding utf8
$code = $LASTEXITCODE

$alive = -not $game.HasExited
$modules = 'unknown'
try {
    $modules = @((Get-Process -Id $game.Id -ErrorAction Stop).Modules |
        Where-Object { $_.ModuleName -match 'apexcheat' } |
        ForEach-Object { $_.ModuleName }) -join ','
} catch {
    $modules = "<exception: $($_.Exception.Message)>"
}

$sticky = Join-Path $PSScriptRoot 'apexcheat.launcher.ini'
$stickyText = if (Test-Path $sticky) { (Get-Content $sticky) -join ' | ' } else { '<no sticky file>' }

Pop-Location

"exit=$code"            | Out-File -FilePath $done -Encoding ascii
"pid=$($game.Id)"       | Out-File -FilePath $done -Encoding ascii -Append
"elevated=$elevated"   | Out-File -FilePath $done -Encoding ascii -Append
"game_alive=$alive"    | Out-File -FilePath $done -Encoding ascii -Append
"apexcheat_modules=$modules" | Out-File -FilePath $done -Encoding ascii -Append
"sticky=$stickyText"   | Out-File -FilePath $done -Encoding ascii -Append
