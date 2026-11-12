$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$p=Start-Process -FilePath $py -ArgumentList @((Join-Path $r 'temp\h403_min_pfn.py')) `
  -Verb RunAs -Wait -PassThru -WindowStyle Hidden
$p.ExitCode | Set-Content (Join-Path $r 'temp\h403_rc.txt')