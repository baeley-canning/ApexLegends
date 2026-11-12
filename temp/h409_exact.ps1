$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.e xe'
$script=Join-Path $r 'temp\h409_dtb_exact.py'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$p=Start-Process $py -ArgumentList @($script) -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content (Join-Path $r 'temp\h409_rc.txt')