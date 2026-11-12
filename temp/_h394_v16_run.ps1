$r = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s = Join-Path $r 'temp\_h394_v16_inner.ps1'
"& '$py' '$r\temp\_h394_v16_probe.py' *> '$r\temp\_h394_v16_console.txt'; `$LASTEXITCODE | Set-Content '$r\temp\_h394_v16_rc.txt'" | Set-Content $s -Encoding ASCII
$p = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $s + '"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\_h394_v16_parent_rc.txt