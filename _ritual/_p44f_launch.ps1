# Launch the staged p44f runner ELEVATED, args passed through verbatim.
# The runner is the evidence producer; this wrapper only does the runas hop
# (same pattern as _p37_ping_task.ps1) so every smoke/live run is one command.
# Usage: powershell -File _ritual\_p44f_launch.ps1 --pid=<n> [--dry[=N]] ...
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $line = '-NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\p44f_run.ps1 ' + ($args -join ' ')
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $line -Verb RunAs -PassThru -Wait
    } catch {
        Write-Host ('elevate failed: ' + $_.Exception.Message)
        exit 5
    }
    exit $p.ExitCode
}
& 'C:\Windows\Temp\p44f_run.ps1' @args
exit $LASTEXITCODE
