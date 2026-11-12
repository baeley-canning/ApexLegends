$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s=Join-Path $r 'temp\h395_run_inner.ps1'
"& '$py' '$r\temp\h395_gdrv_object.py' *> '$r\temp\h395_stdout.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h395_rc.txt'" | Set-Content $s -Encoding ASCII
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\h395_parent_rc.txt