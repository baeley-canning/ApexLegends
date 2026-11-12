# h388_matrix.ps1 -- run the h388 matrix validation ELEVATED.
#
# Read-only: no service/driver/reboot/CI/game writes. The probe opens GIOV3,
# re-reads only the candidate windows listed by the current qk_image log, and
# writes temp\_h388_out.txt itself. It does not start or stop anything.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\h388_matrix.ps1
#       [-Log <qk_image log>] [-Out <probe output>]

param(
    [string]$Log = '',
    [string]$Out = '',
    [switch]$RequestElevation
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$probe = Join-Path $root 'temp\_h388_matrix_validate.py'
$status = Join-Path $root 'temp\_h388_launcher.txt'
$consoleLog = Join-Path $root 'temp\_h388_console.txt'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'

if (-not (Test-Path -LiteralPath $py -PathType Leaf)) { throw 'Verified Python 3.12 interpreter missing' }
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw 'h388 probe missing' }

$elevation = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($RequestElevation -and -not $elevation) {
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'),'-RequestElevation')
    try {
        $request = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait -PassThru
        'elevated_child_exit=' + $request.ExitCode + ' requested=' + (Get-Date -Format o) |
            Set-Content -LiteralPath $status -Encoding ascii
        exit $request.ExitCode
    } catch {
        'elevation_request_cancelled_or_failed=' + $_.Exception.Message |
            Set-Content -LiteralPath $status -Encoding ascii
        exit 2
    }
}
if (-not $elevation) {
    throw 'Read-only physical access requires elevation. No automatic elevation, driver start, or state mutation is performed.'
}

if (-not $Log) { $Log = Join-Path $root 'temp\_act_qk_image_live2.txt' }
if (-not $Out) { $Out = Join-Path $root 'temp\_h388_out.txt' }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $py
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$arguments = '-u "' + $probe + '" --no-elevate --log "' + $Log + '" --out "' + $Out + '"'
$psi.Arguments = $arguments
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
'start=' + (Get-Date -Format o) + ' child_pid=' + $p.Id + ' log=' + $Log |
    Set-Content -LiteralPath $status -Encoding ascii
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$completed = $p.WaitForExit(120000)
if (-not $completed) {
    try { $p.Kill() } catch { 'kill_failure=' + $_.Exception.Message | Add-Content -LiteralPath $status }
    [void]$p.WaitForExit(5000)
    $rc = 9
    'VERDICT: FAIL -- launcher timeout, child killed; unfinished gates are SKIPPED, not PASS' |
        Add-Content -LiteralPath $status
} else {
    $rc = $p.ExitCode
}
Set-Content -LiteralPath $consoleLog -Value ($stdout + [Environment]::NewLine + $stderr) -Encoding ascii
'rc=' + $rc + ' completed=' + $completed + ' finished=' + (Get-Date -Format o) | Add-Content -LiteralPath $status
Get-Content -LiteralPath $status
exit $rc
