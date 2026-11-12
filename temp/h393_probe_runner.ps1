$r = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s = Join-Path $r 'temp\h393_probe_inner.ps1'
"& '$py' '$r\ext\qk_h393.py' *> '$r\temp\h393_proc_stdout.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h393_probe_rc.txt'" | Set-Content $s -Encoding ASCII
& "$env:SystemRoot\System32\cmd.exe" /c ('echo ready')
$p = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $s + '"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\h393_parent_rc.txt