$r = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$runner = Join-Path $r 'temp\_h393_map_inner.ps1'
"& '$py' '$r\temp\_h393_map_control.py' *> '$r\temp\_h393_map_console.txt'; `$LASTEXITCODE | Set-Content '$r\temp\_h393_map_rc.txt'" | Set-Content $runner -Encoding ASCII
$p = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $runner + '"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\_h393_map_parent_rc.txt