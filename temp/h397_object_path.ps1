# h397: current ProcessFull query returns the valid process record; only then
# do guarded gdrv3 MapK reads. No ApexDrv/custom driver load/start/stop.
$r='C:\Users\New User\OneDrive\Desktop\cheating'
$p=Start-Process -FilePath "$r\QwenKernPremium\build\qk_process_query.exe" `
  -ArgumentList '--pid','14008' -Verb RunAs -Wait -PassThru -NoNewWindow
$p.ExitCode | Set-Content "$r\temp\h397_object_path.rc"