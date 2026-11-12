$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$script=Join-Path $r 'temp\h401_run.py'
$inner=Join-Path $r 'temp\h401_cmdline_inner.ps1'
$out=Join-Path $r 'temp\h401_cmdline.txt'
"& '$py' '$script' *>> '$out'" | Set-Content $inner -Encoding ASCII
$arg='-NoProfile -ExecutionPolicy Bypass -File "'+$inner+'"'
$p=Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList $arg
Write-Output ('parent='+($p.ExitCode))