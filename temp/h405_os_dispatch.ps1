$r='C:\Users\New User\OneDrive\Desktop\cheating'
$s=Join-Path $r 'temp\h405_os_dispatch_inner.ps1'
"& '$r\\QwenKernPremium\\build\\h405_native.exe' '--pid','14624' *> '$r\\temp\\h405_dispatch.txt'; `$LASTEXITCODE | Set-Content '$r\\temp\\h405_dispatch_rc.txt'" | Set-Content -LiteralPath $s -Encoding ASCII
$p=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode|Set-Content $r\temp\h405_dispatch_parent_rc.txt