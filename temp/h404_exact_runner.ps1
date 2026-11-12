$r='C:\Users\New User\OneDrive\Desktop\cheating'
$p='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$script=Join-Path $r 'temp\h404_exact_handle.py'
Start-Process -FilePath $p -ArgumentList @($script) -Verb RunAs -Wait