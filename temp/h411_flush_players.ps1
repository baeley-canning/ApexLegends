$r='C:\Users\New User\OneDrive\Desktop\cheating'
$e=Join-Path $r 'QwenKernPremium\build\qk_player_probe.exe'
$o=Join-Path $r 'temp\h411_players_live.txt'
$s=Join-Path $r 'temp\h411_flush_inner.ps1'
"& '$e' '--pid','14624' *> '$o' ; `$LASTEXITCODE | Set-Content '$r\\temp\\h411_live_rc.txt'" | Set-Content $s -Encoding ASCII
$p=Start-Process 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$s) -Verb RunAs -Wait -PassThru
Write-Output ('rc='+$p.ExitCode)
if(Test-Path $o){Get-Content $o -Tail 55 | Out-String | Write-Output}