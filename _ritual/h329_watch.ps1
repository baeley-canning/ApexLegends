# h329_watch.ps1 - background sampler for the live h329 fire (survives terminal recycling).
# Writes one line / 10 s: game count, fire pid presence, fire out mtime. Exits 3 s after the fire
# process disappears (fire emits its out just before exiting). Start it detached; poll the txt.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log  = Join-Path $here 'h329_watch.txt'
Set-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' watch start')
while ($true) {
    $line = (Get-Date -f 'HH:mm:ss') + ' game=' + @(Get-Process r5apex_dx12 -EA 0).Count + ' fire=' + @(Get-Process -Id 39000 -EA 0).Count + ' out=' + (Get-Item (Join-Path $here 'h329_fire_readonly.out')).LastWriteTime.ToString('HH:mm:ss')
    Add-Content -LiteralPath $log -Value $line
    if (-not @(Get-Process -Id 39000 -EA 0).Count) { Add-Content -LiteralPath $log -Value ('-- fire exited ' + (Get-Date -f 'HH:mm:ss') + ' --'); Start-Sleep -Seconds 3; break }
    Start-Sleep -Seconds 10
}
