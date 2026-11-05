# _h227_inject.ps1 - run apex_launcher.exe --inject --pid=<game> with elevation.
# Same outer/inner split as h1: -Verb RunAs cannot carry a redirect, so the OUTER process
# only elevates; the INNER (already elevated) runs the launcher with stdout/stderr redirect.
# No state mutation by us; launcher does the injection. Own files, own verdict line.
# Usage: powershell -File _h227_inject.ps1 [-Inner]
param([switch]$Inner, [int]$GamePid)
$b   = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
$exe = Join-Path $b 'apex_launcher.exe'
$out = Join-Path $PSScriptRoot '_h227_out.txt'   # launcher stdout (Start-Process truncates it)
$err = Join-Path $PSScriptRoot '_h227_err.txt'
$run = Join-Path $PSScriptRoot '_h227_run.txt'   # our own stamps, never truncated by the redirect
function W($s) { ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) | Add-Content -LiteralPath $run -Encoding UTF8 }
if (-not $Inner) {
    $adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    $gp = if ($GamePid) { $GamePid } else { (@(Get-Process r5apex_dx12 -EA 0)[0]).Id }
    if (-not $gp) { 'no game pid' | Set-Content $run; exit 1 }
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Inner -GamePid ' + $gp
    if ($adm) { Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden }
    else { Start-Process powershell.exe -ArgumentList $a -Verb RunAs -Wait }
    exit 0
}
W ('RUN pid=' + $GamePid + ' up=' + [int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes) + 'min'
W ('pre drv=' + (((& sc.exe query apexdrv | Select-String 'STATE') -replace '\s+', ' ').Trim()))
W ('pre title=' + (@(Get-Process -Id $GamePid -EA 0)[0]).MainWindowTitle)
W ('exe=' + (Test-Path $exe) + ' dll=' + (Test-Path (Join-Path $b 'apexcheat.dll')))
$p = Start-Process -FilePath $exe -ArgumentList ('--inject --pid=' + $GamePid) -WorkingDirectory $b -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
W ('launched pid=' + $p.Id)
$p.WaitForExit(180000) | Out-Null
W ('EXIT=' + $(try { $p.ExitCode } catch { '?' }))
W ('post game alive=' + [bool](Get-Process -Id $GamePid -EA 0) + ' drv=' + (((& sc.exe query apexdrv | Select-String 'STATE') -replace '\s+', ' ').Trim()))
W 'END'
