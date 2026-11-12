$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s=Join-Path $r 'temp\h399_inner.ps1'
"& '$py' '$r\temp\h399_gdrv_census.py' *> '$r\temp\h399_console.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h399_rc.txt'"|Set-Content $s -Encoding ASCII
$p=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\h399_parent_rc.txt