$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s=Join-Path $r 'temp\h395_map_inner.ps1'
"& '$py' '$r\temp\h395_gdrv_map.py' *> '$r\temp\h395_map_console.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h395_map_rc.txt'" | Set-Content $s -Encoding ASCII
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\h395_map_parent_rc.txt