$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$runner = Join-Path $root 'temp\_h393_inner.ps1'
"& '$py' '$root\temp\_h393_layout.py' *> '$root\temp\_h393_console.txt'; `$LASTEXITCODE | Set-Content '$root\temp\_h393_rc.txt'" | Set-Content $runner -Encoding ASCII
$p = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $runner + '"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $root\temp\_h393_parent_rc.txt