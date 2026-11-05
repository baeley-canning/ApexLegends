# Launch ext\decoyscan.py ELEVATED, args passed through verbatim (p44f discovery).
# Same runas hop as _p44f_launch.ps1; scan output goes to _ritual\p44f_decoy.txt.
# Usage: powershell -File _ritual\_p44f_dlaunch.ps1 --pid=0x5c84 [--lo= --hi=]
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
if (-not $adm) {
    $line = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" ' + ($args -join ' ')
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $line -Verb RunAs -PassThru -Wait
    } catch {
        Write-Host ('elevate failed: ' + $_.Exception.Message)
        exit 5
    }
    exit $p.ExitCode
}
$py  = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$src = Join-Path $repo 'ext\decoyscan.py'
$env:DUMP_OUT  = 'p44f_decoy.txt'
$env:DUMP_PROG = 'p44f_dprog.txt'
& $py -u $src @args
exit $LASTEXITCODE
