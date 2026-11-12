# h382_vp.ps1 -- run the h382 ViewRender read-back ELEVATED.
#
# Why: \\.\GIOV3 has DACL D:P(A;;GA;;;SY)(A;;GA;;;BA), so an unprivileged python
# gets errno 5 on CreateFileW and every physical gate is skipped.  The gdrv3
# service is already RUNNING (STATE 4) -- this launcher starts nothing.
#
# Read-only: the probe opens the device, reads only addresses inside the RAM map's
# interval set (R10), and writes temp\_h382_out.txt itself.  No service change, no
# boot flag, no driver load, no reboot (R1/R2 untouched).
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\h382_vp.ps1

param([string]$Py = '')

$root = Split-Path -Parent $PSScriptRoot
$probe = Join-Path $root 'temp\_h382_vp_live.py'
$log = Join-Path $root 'temp\_h382_console.txt'

$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
       ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $adm) {
    'not elevated -> relaunching via UAC' |
        Set-Content -LiteralPath (Join-Path $root 'temp\_h382_launch.txt')
    $al = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    Start-Process -FilePath 'powershell.exe' -ArgumentList $al -Verb RunAs
    exit 0
}

if (-not $Py) { $Py = (Get-Command python -ErrorAction SilentlyContinue).Source }
if (-not $Py) {
    'no python on PATH' | Set-Content -LiteralPath $log
    exit 2
}

Set-Location -LiteralPath $root
't0 ' + (Get-Date -Format 'HH:mm:ss') | Set-Content -LiteralPath $log
& $Py $probe *>> $log
('exit=' + $LASTEXITCODE) | Add-Content -LiteralPath $log
