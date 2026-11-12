$r='C:\Users\New User\OneDrive\Desktop\cheating'
$s=Join-Path $r 'temp\h410_run_inner.ps1'
"& '$r\QwenKernPremium\build\qk_player_probe.exe' '--pid','14624' *> '$r\temp\h410_players.txt'"|Set-Content -LiteralPath $s -Encoding ASCII
$p=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
Get-Content "$r\temp\h410_players.txt" -Tail 75 -ErrorAction SilentlyContinue | Write-Host