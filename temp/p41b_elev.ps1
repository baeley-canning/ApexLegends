# p41b_elev.ps1 - try sudo and RunAs against a readable-path probe. Read-only.
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\p41j.txt'
function L($m) { Add-Content -LiteralPath $log -Value ('{0:HH:mm:ss} {1}' -f (Get-Date), $m) -Encoding utf8 }
Set-Content -LiteralPath $log -Value ('p41b {0:HH:mm:ss}' -f (Get-Date)) -Encoding utf8
$probe = 'C:\Windows\Temp\p41_elev.ps1'
$res   = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\p41_elev.txt'
Remove-Item -LiteralPath $res -ErrorAction 0

# --- A: sudo -------------------------------------------------------------
$sA = & sudo.exe powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probe -Tag sudo 2>&1
L ('A_rc=' + $LASTEXITCODE + ' out=' + ($sA -join ' / '))
Start-Sleep -Seconds 3
L ('A_probe=' + (try { (Get-Content -LiteralPath $res -ErrorAction Stop) -join ' | ' } catch { 'MISSING' }))

# --- B: RunAs, with diagnostics -----------------------------------------
Remove-Item -LiteralPath $res -ErrorAction 0
try {
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ErrorAction Stop `
         -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + $probe + ' -Tag runas')
    L ('B_pid=' + $p.Id)
    $null = $p.WaitForExit(8000)
    L ('B_exited=' + $p.HasExited + ' code=' + (try { $p.ExitCode } catch { 'n/a' }))
} catch { L ('B_ERR=' + $_.Exception.Message) }
Start-Sleep -Seconds 2
L ('B_probe=' + (try { (Get-Content -LiteralPath $res -ErrorAction Stop) -join ' | ' } catch { 'MISSING' }))
L 'done'
