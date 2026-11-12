$r='C:\Users\New User\OneDrive\Desktop\cheating'
$s=Join-Path $r 'temp\h398_query2_inner.ps1'
"& '$r\QwenKernPremium\build\qk_dump_objects.exe' '--pid','14624' *> '$r\temp\h398_query2.txt'; `$LASTEXITCODE | Set-Content '$r\temp\h398_query2_rc.txt'" | Set-Content $s -Encoding ASCII
$p=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\h398_query2_parent_rc.txt