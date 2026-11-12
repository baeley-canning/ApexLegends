$r='C:\Users\New User\柞o\Doom'
$r='C:\Users\New User\OneDrive\大師bunga'
$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s=Join-Path $r 'temp\h406_inner.ps1'
"& '$py' '$r\temp\h406_self_kernel.py' *> '$r\temp\h406_output.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h406_rc.txt'"|Set-Content $s -Encoding ASCII
$p=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode|Set-Content $r\temp\h406_parent_rc.txt