$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.e xe'
$script=Join-Path $r 'temp\h402_pfn_priv.py'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$p=Start-Process -FilePath $py -ArgumentList $script -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content "$r\temp\h402_pfn_priv_rc.txt"