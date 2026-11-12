$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s=Join-Path $r 'temp\h399_pfninner.ps1'
"& '$py' '$r\temp\h399_pfngate.py' *> '$r\temp\h399_pfnconsole.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h399_pfnrc.txt'" | Set-Content $s -Encoding ASCII
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\h399_pfnparent_rc.txt