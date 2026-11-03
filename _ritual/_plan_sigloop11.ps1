# _plan_sigloop11.ps1 - detached 5-minute signature loop until 22:15. Read-only, survives shell restarts.
# NB: the live instance was started from the 22.15 variant (ends 22:09); 22.25 is the corrected form.
$sig = Join-Path $PSScriptRoot '_plan_sig11.ps1'
$stop = (Get-Date).Date.AddHours(22.25)
& $sig
while ((Get-Date) -lt $stop) {
    Start-Sleep -Seconds 300
    & $sig
}
