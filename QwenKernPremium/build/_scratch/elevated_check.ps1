# Runs the launcher ELEVATED against the live r5apex_dx12.exe.
# The non-elevated run of 2026-10-26 got ERROR_ACCESS_DENIED (5) on OpenProcess
# and an empty module snapshot, so no verdict from that run can be trusted.
$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
"elevated=$( $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) )" |
    Out-File -Encoding utf8 elevated_flag.txt

$apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Id
"APEX=$apex" | Out-File -Encoding utf8 e_apex.txt
if (-not $apex) { exit 2 }

& .\apex_launcher.exe --probe --pid=$apex *>&1 | Out-File -Encoding utf8 e1_probe.txt
"PROBE_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append e1_probe.txt

& .\apex_launcher.exe --inject --no-wait --pid=$apex *>&1 | Out-File -Encoding utf8 e2_ladder.txt
"LADDER_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append e2_ladder.txt

"sticky:" | Out-File -Encoding utf8 e3_sticky.txt
Get-Content .\apexcheat.launcher.ini -ErrorAction SilentlyContinue |
    Out-File -Encoding utf8 -Append e3_sticky.txt
