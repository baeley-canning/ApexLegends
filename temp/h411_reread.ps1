$r='C:\Users\New User\OneDrive\Desktop\cheating'
$e=Join-Path $r 'QwenKernPremium\build\qk_player_probe.exe'
$p=Start-Process -FilePath $e -ArgumentList '--pid','14624' -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content "$r\temp\h411_players_rc.txt"