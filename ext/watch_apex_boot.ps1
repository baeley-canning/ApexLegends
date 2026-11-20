# watch_apex_boot.ps1 -- READ-ONLY boot observer (5 min horizon, 4 s cadence).
# Appends presence/RAM/window-title of r5apex_dx12 to temp\watch_apex_boot.txt.
# Exists because the interactive console's output capture dies on >6 s sleeps;
# a detached writer + file reads are the R3-safe verdict channel here.
$f = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) `
               'temp\watch_apex_boot.txt'
"=== watch start $(Get-Date -Format HH:mm:ss) ===" | Set-Content -LiteralPath $f
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    $p = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue
    if ($p) {
        Add-Content -LiteralPath $f ("{0} UP pid={1} ram={2}MB title='{3}'" -f `
            (Get-Date -Format HH:mm:ss), $p.Id, [math]::Round($p.WorkingSet64/1MB), `
            $p.MainWindowTitle)
        if ($p.MainWindowTitle -ne '') {
            Add-Content -LiteralPath $f 'WATCH_RESULT: window-present'
            break
        }
    }
    else {
        Add-Content -LiteralPath $f ("{0} absent" -f (Get-Date -Format HH:mm:ss))
    }
    Start-Sleep 4
}
Add-Content -LiteralPath $f 'WATCH_DONE'
