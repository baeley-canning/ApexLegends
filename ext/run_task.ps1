# run_task.ps1 -- create+run+delete a SYSTEM scheduled task that runs a python
# script, then wait for its output file.  Usage (from an elevated shell):
#   .\run_task.ps1 -Script t_g1.py -Output out_g1.txt
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [Parameter(Mandatory = $true)][string]$Output,
    [string]$Python = "",
    [int]$TimeoutSec = 180,
    [string]$LogFile = ""
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Python) {
    $Python = (Get-Command python.exe).Source
}
$task = "ApexRun_" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$outpath = Join-Path $here $Output
$errpath = Join-Path $here ($Output + ".tasklog")
if (Test-Path $outpath) { Remove-Item $outpath -Force }
if (Test-Path $errpath) { Remove-Item $errpath -Force }
# cmd wrapper so stderr + crash output always lands in the tasklog
$arg = '/c ""{0}" "{1}" --elevated > "{2}" 2>&1"' -f $Python, (Join-Path $here $Script), $errpath
$act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $arg -WorkingDirectory $here
Register-ScheduledTask -TaskName $task -Action $act -User "SYSTEM" `
    -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName $task
$t0 = Get-Date
while (-not (Test-Path $errpath) -and ((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
    Start-Sleep 1
}
Start-Sleep 2
Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
$rep = @()
$rep += ("python = {0}" -f $Python)
if (Test-Path $errpath) { $rep += "--- tasklog"; $rep += (Get-Content $errpath) }
if (Test-Path $outpath) { $rep += "--- result"; $rep += (Get-Content $outpath) }
$rep = $rep -join [Environment]::NewLine
if ($LogFile) {
    Set-Content -Path (Join-Path $here $LogFile) -Value $rep -Encoding UTF8
}
Write-Output $rep
