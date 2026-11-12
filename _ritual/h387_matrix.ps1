# h387_mutex NOT used: h378's mutex timeout is not a permitted shortcut here.
# The only child this launcher controls is the new Python process it creates.
# Read only: no service/driver/reboot/CI/game writes; no DTB/ApexDrv discovery.
param(
    [Parameter(Mandatory = $true)][string]$Pe,
    [string]$ImagePa = '',
    [ValidatePattern('^[A-Za-z0-9]+$')][string]$Label = 'h387',
    [switch]$Preflight,
    [switch]$RequestElevation
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$probe = Join-Path $root 'temp\_h387_matrix_live.py'
$log = Join-Path $root ('temp\_h387_' + $Label + '_console.txt')
$status = Join-Path $root ('temp\_h387_' + $Label + '_launcher.txt')
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
if (-not (Test-Path -LiteralPath $py -PathType Leaf)) { throw 'Verified Python 3.12 interpreter missing' }
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw 'h387 probe missing' }
if (-not (Test-Path -LiteralPath $Pe -PathType Leaf)) { throw 'Exact same-build PE input missing' }
$elevation = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($RequestElevation -and -not $elevation) {
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'),
        '-Pe',('"' + $Pe + '"'),'-Label',$Label)
    if ($ImagePa) { $args += @('-ImagePa',$ImagePa) }
    if ($Preflight) { $args += '-Preflight' }
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
if (-not $Preflight -and -not $elevation) {
    throw 'Read-only physical access requires elevation. No automatic elevation, driver start, or state mutation is performed.'
}
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $py
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$arguments = '-u "' + $probe + '" --label ' + $Label + ' --pe "' + $Pe + '"'
if ($Preflight) { $arguments += ' --preflight' }
elseif ($ImagePa) { $arguments += ' --image-pa=' + $ImagePa }
$psi.Arguments = $arguments
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
'start=' + (Get-Date -Format o) + ' child_pid=' + $p.Id + ' preflight=' + $Preflight + ' pe=' + $Pe |
    Set-Content -LiteralPath $status -Encoding ascii
# The probe prints bounded evidence. Avoid PowerShell 5.1 *>> UTF-16 log pollution.
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$completed = $p.WaitForExit(90000)
if (-not $completed) {
    # No tree was spawned by this launcher. Kill only this boundedly owned child.
    try { $p.Kill() } catch { 'kill_failure=' + $_.Exception.Message | Add-Content -LiteralPath $status }
    [void]$p.WaitForExit(5000)
    $rc = 9
    'VERDICT: FAIL -- launcher timeout, child killed; unfinished gates are SKIPPED, not PASS' |
        Add-Content -LiteralPath $status
} else {
    $rc = $p.ExitCode
}
Set-Content -LiteralPath $log -Value ($stdout + [Environment]::NewLine + $stderr) -Encoding ascii
'rc=' + $rc + ' completed=' + $completed + ' finished=' + (Get-Date -Format o) | Add-Content -LiteralPath $status
Get-Content -LiteralPath $status
exit $rc
