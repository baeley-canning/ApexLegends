# Only known-privileged-receipt resolution, no driver/service change.
$r='C:\Users\New User\OneDrive\Desktop\cheating'
$p=Start-Process -FilePath "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe" `
  -ArgumentList @((Join-Path $r 'temp\h407_phys_exact.py')) -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content "$r\temp\h407_resolve_dtb.rc"