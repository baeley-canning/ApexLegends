# Query-only, same process query as before but with the required admin token.
$r = 'C:\Users\New User\OneDrive\Desktop\cheating'
$runner = Join-Path $r 'temp\_h393_query_inner.ps1'
"& '$r\QwenKernPremium\build\qk_process_query.exe' --pid 14008 *> '$r\temp\_h393_query.txt'; `$LASTEXITCODE | Set-Content '$r\temp\_h393_query_rc.txt'" | Set-Content $runner -Encoding ASCII
$p = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $runner + '"') -Verb RunAs -Wait -PassThru
$p.ExitCode | Set-Content $r\temp\_h393_query_parent_rc.txt