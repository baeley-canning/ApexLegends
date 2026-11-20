# _ritual/detach_run.ps1 -- launch a long probe OUTSIDE the VS Code terminal so
# shell-integration churn cannot kill it.  Windows PowerShell 5.1 safe:
# the script path MUST ride inside an explicitly quoted arg string
# (Start-Process -ArgumentList array entries are NOT re-quoted for you).
#
# usage:  powershell -NoProfile -ExecutionPolicy Bypass -File detach_run.ps1 `
#            -Script C:\path\probe.py [-WorkDir C:\path] [-Tag mytag]
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$WorkDir = (Split-Path $Script -Parent),
    [string]$Tag = "probe",
    [string]$PyArgs = ""
)
$stem  = [IO.Path]::GetFileNameWithoutExtension($Script)
$root  = Split-Path $WorkDir -Parent
$tstd  = Join-Path $root 'temp'
if (-not (Test-Path $tstd)) { $tstd = $WorkDir }
$cout  = Join-Path $tstd ('{0}_console.txt' -f $stem)
$cerr  = Join-Path $tstd ('{0}_err.txt'    -f $stem)
$argstr = '-u "{0}" {1}' -f $Script, $PyArgs
$p = Start-Process -FilePath python -ArgumentList $argstr `
        -WorkingDirectory $WorkDir -RedirectStandardOutput $cout `
        -RedirectStandardError $cerr -WindowStyle Hidden -PassThru
Set-Content -Path (Join-Path $tstd ('{0}_pid.txt' -f $Tag)) -Value $p.Id
Write-Output ('DETACHED {0} pid={1}' -f $Tag, $p.Id)
exit 0
