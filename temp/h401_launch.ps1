$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$command='& "'+$py+'" "'+$r+'temp\h401_run.py"'
$p=Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
  -ArgumentList ('-NoProfile','-ExecutionPolicy','Bypass','-Command',$command)
$p.ExitCode | Set-Content "$r\temp\h401_launch_rc.txt"