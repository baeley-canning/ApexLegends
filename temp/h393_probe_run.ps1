$r = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s = Join-Path $r 'temp\_h393_inner2.ps1'
"& '$py' '$r\ext\qk_h393.py' *> '$r\temp\_h393_runner.txt'; `$LASTEXITCODE | Set-Content '$r\temp\_h393_probe_rc.txt'" | Set-Content $s -Encoding ASCII
$p = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $s + '"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\_h393_probe_parent_rc.txt