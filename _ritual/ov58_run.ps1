# ov58_run.ps1 - run the overlay test harness in a space-free cwd and capture
# the exit code plus the produced files.  R5: own directory, own output files.
# The --outdir value is passed quoted; unquoted it splits on "New User".
param(
    [int]$MenuTab = -1,
    [string]$OutDir = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\ov58_cwd'
)
$ErrorActionPreference = 'Stop'
$exe = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\overlay_test.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "missing $exe" }
[void][IO.Directory]::CreateDirectory($OutDir)

$argLine = '--outdir "' + $OutDir + '"'
if ($MenuTab -ge 0) { $argLine += ' --menu-tab ' + $MenuTab }

$p = Start-Process -FilePath $exe -ArgumentList $argLine -WorkingDirectory $OutDir `
                   -PassThru
$null = $p.WaitForExit(180000)
$lines = @("exit=$($p.ExitCode)", "args=$argLine")
Get-ChildItem -LiteralPath $OutDir | Sort-Object Name | ForEach-Object {
    $lines += ("{0} {1}" -f $_.Name, $_.Length)
}
[IO.File]::WriteAllText((Join-Path $OutDir 'ov58_exit.txt'), ($lines -join "`r`n"))
$lines -join "`n"
