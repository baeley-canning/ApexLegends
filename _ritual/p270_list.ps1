# p270_list.ps1 - read-only provider-id -> name map from kdu's own db (host, no driver load).
$o = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_list.csv'
$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_list_rc.txt'
Remove-Item -LiteralPath $o, $r -EA 0
# kdu -listcsv prints to stdout only, and needs an elevated manifest; capture through cmd and
# keep the console alive long enough for the redirect to flush.
$p = Start-Process -FilePath 'C:\Windows\System32\cmd.exe' -ArgumentList @('/c', 'C:\p37vm\payload\kdu.exe -listcsv > "' + $o + '" 2>&1') -WorkingDirectory 'C:\p37vm\payload' -Verb RunAs -Wait -PassThru -WindowStyle Hidden
'rc=' + $p.ExitCode + ' exists=' + (Test-Path $o) + ' len=' + $(if (Test-Path $o) { (Get-Item $o).Length } else { -1 }) | Set-Content -LiteralPath $r
