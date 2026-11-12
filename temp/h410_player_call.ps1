$exe=Resolve-Path '.\QwenKernPremium\build\qk_player_probe.exe' | Select-Object -Expand Path
$o=Join-Path (Get-Location) 'temp\current_players.txt'
$inner=Join-Path (Get-Location) 'temp\current_players_inner.ps1'
"& '$exe' '--pid','14624' *> '$o'" | Set-Content -LiteralPath $inner -Encoding ASCII
$p=Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList ('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$inner`"")
Write-Output ('rc='+$p.ExitCode)
if(Test-Path $o){Get-Content $o -Tail 70 | Out-String | Write-Output}