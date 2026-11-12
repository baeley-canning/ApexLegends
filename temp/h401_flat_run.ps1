$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s=Join-Path $r 'temp\h401_flat_inner.ps1'
"& '$py' '$r\temp\h401_flat_objects.py' *> '$r\temp\h401_flat_console.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h401_flat_rc.txt'" | Set-Content $s -Encoding ASCII
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\h401_flat_parent_rc.txt