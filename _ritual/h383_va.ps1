# h383_va.ps1 -- run the h383 ViewRender read-back ELEVATED.
#
# Why: \\.\GIOV3 has DACL D:P(A;;GA;;;SY)(A;;GA;;;BA), so an unprivileged python
# gets errno 5 on CreateFileW and every physical gate is skipped.  gdrv3 is
# already RUNNING (STATE 4) -- this launcher starts nothing and changes nothing.
#
# h383 also needs \\.\ApexDrv for one cheap (dtb, base) IOCTL; that service is
# STOPPED, so qk_va.get_map() falls through to its discovery sweep (~1-3 min the
# first time, then temp\qk_dtb_<pid>.txt makes every later run instant).
#
# Read-only: the probe opens the device, reads only inside the RAM map's interval
# set (R10), and writes temp\_h383_out.txt itself.  No service change, no boot
# flag, no driver load, no reboot (R1/R2 untouched).
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\h383_va.ps1

param([string]$Py = '', [string]$Extra = '')

$root = Split-Path -Parent $PSScriptRoot
$probe = Join-Path $root 'temp\_h383_va_live.py'
$log = Join-Path $root 'temp\_h383_console.txt'

$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
       ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $adm) {
    ('not elevated -> relaunching via UAC  ' + (Get-Date -Format 'HH:mm:ss')) |
        Set-Content -LiteralPath (Join-Path $root 'temp\_h383_launch.txt')
    $al = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($Extra) { $al += @('-Extra', ('"{0}"' -f $Extra)) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $al -Verb RunAs
    exit 0
}

if (-not $Py) { $Py = (Get-Command python -ErrorAction SilentlyContinue).Source }
if (-not $Py) {
    'no python on PATH' | Set-Content -LiteralPath $log
    exit 2
}

Set-Location -LiteralPath $root
('t0 ' + (Get-Date -Format 'HH:mm:ss') + '  elevated=yes  py=' + $Py + '  extra=' + $Extra) |
    Set-Content -LiteralPath $log
$extraArgs = @()
if ($Extra) { $extraArgs = @($Extra -split '\s+' | Where-Object { $_ }) }
& $Py $probe @extraArgs *>> $log
('exit=' + $LASTEXITCODE + '  t1=' + (Get-Date -Format 'HH:mm:ss')) |
    Add-Content -LiteralPath $log
