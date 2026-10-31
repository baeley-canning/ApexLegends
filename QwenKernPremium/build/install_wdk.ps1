# ============================================================================
# build\install_wdk.ps1 — install the WDK 10.0.26100 so apexdrv.sys can be
# compile-verified on this box.  Run ELEVATED, in the background:
#
#   Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile',
#     '-ExecutionPolicy','Bypass','-File','...\build\install_wdk.ps1'
#
# Writes build\phase1_evidence\wdk_install.txt and ...\wdk_done.txt so the
# non-elevated shell can poll instead of blocking on a UAC prompt + download.
# ============================================================================
$ErrorActionPreference = 'Continue'

$ev  = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\phase1_evidence'
$log = Join-Path $ev 'wdk_install.txt'
Remove-Item (Join-Path $ev 'wdk_done.txt') -ErrorAction SilentlyContinue

"== WDK install attempt $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
"elevated: $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" |
    Out-File -Encoding utf8 -Append $log

# The winget package is the VS-integration-aware installer from Microsoft; the
# version matches the already-installed Windows 11 SDK 10.0.26100.
winget install --id Microsoft.WindowsWDK.10.0.26100 --exact --silent `
    --accept-package-agreements --accept-source-agreements *>&1 |
    Out-File -Encoding utf8 -Append $log
"winget EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append $log

# Verify the pieces the driver project actually needs, not the exit code.
foreach ($probe in @(
    'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\km',
    'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\km\x64',
    'C:\Program Files (x86)\Windows Kits\10\build',
    'C:\Program Files (x86)\Windows Kits\10\build\WindowsDriver.Default.props')) {
    "$(Test-Path -LiteralPath $probe)  $probe" | Out-File -Encoding utf8 -Append $log
}
Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\build' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Name | Out-File -Encoding utf8 -Append $log

'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'wdk_done.txt')
