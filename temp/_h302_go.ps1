# h302 launcher: parse-check the probe, then start it hidden (own transcript, own log).
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$probe = Join-Path $root '_ritual\h302_elev.ps1'
$log   = Join-Path $root 'temp\_h302_launch.txt'
$err = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($probe, [ref]$null, [ref]$err)
$m = 'parse_errors=' + @($err).Count
foreach ($e in @($err)) { $m += ' | L' + $e.Extent.StartLineNumber + ': ' + $e.Message }
$m | Out-File -LiteralPath $log -Encoding ascii
if (@($err).Count -gt 0) { Write-Output $m; return }
$p = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $probe + '"') -WindowStyle Hidden -PassThru
('pid=' + $p.Id + ' started at ' + (Get-Date -f 'HH:mm:ss')) | Out-File -LiteralPath $log -Encoding ascii -Append
Write-Output ('parse_errors=0 pid=' + $p.Id)
