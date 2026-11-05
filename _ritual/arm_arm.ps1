# arm_arm.ps1 -- re-arm the elevated cmd.txt listener as a fully detached scheduled task.
# Task scheduler is the parent, so it survives terminal reaping. Read-back: query the task,
# then prove liveness by dropping a probe command and waiting for its output file.
$repo  = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log   = Join-Path $repo 'temp\arm.log'
$name  = 'cheat_p64_arm'
$ps    = Join-Path $repo 'ext\p64_arm.ps1'
$probe = Join-Path $repo 'temp\arm_probe.txt'
Remove-Item -LiteralPath $probe -EA 0
"=== arm $(Get-Date -Format o) ===" | Set-Content -Encoding utf8 $log
function L([string]$t) { $t | Out-File -Append -Encoding utf8 $log }

$tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ps + '"'
$c = schtasks.exe /create /tn $name /tr $tr /sc once /st 00:00 /rl highest /f 2>&1
L ("CREATE rc=$LASTEXITCODE :: " + ($c -join ' | '))
$r = schtasks.exe /run /tn $name 2>&1
L ("RUN rc=$LASTEXITCODE :: " + ($r -join ' | '))
Start-Sleep -Seconds 4
$q = schtasks.exe /query /tn $name /fo list 2>&1
L ('QUERY :: ' + ($q -join ' | '))

# liveness probe through the queue
Set-Content -LiteralPath (Join-Path $repo 'temp\cmd.txt') -Encoding Unicode -Value ('"ARM_OK $(Get-Date -Format o)" | Out-File -Encoding ascii temp\arm_probe.txt')
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $probe) { $ok = $true; break }
}
L ('PROBE file=' + $ok + ' waited_ms=' + ($i * 500))
if ($ok) { L ('PROBE content=' + ((Get-Content $probe -Raw).Trim())) }
L 'arm end'
