$o = 'C:\p37vm\payload\list.csv'
Remove-Item -LiteralPath $o -EA 0
$p = Start-Process -FilePath 'C:\Windows\System32\cmd.exe' -ArgumentList @('/c', 'C:\p37vm\payload\kdu.exe -listcsv ' + $o + ' > C:\p37vm\payload\list.log 2>&1') -WorkingDirectory 'C:\p37vm\payload' -Verb RunAs -Wait -PassThru -WindowStyle Hidden
'rc=' + $p.ExitCode + ' len=' + $(if (Test-Path $o) { (Get-Item $o).Length } else { -1 }) | Set-Content 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_usage_rc.txt'
