$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
Set-Location -LiteralPath $repo
$log = Join-Path $repo 'temp\_p87_t.log'
Remove-Item -LiteralPath $log -EA 0
"A start $(Get-Date -Format HH:mm:ss.fff)" | Out-File -Append -Encoding utf8 $log
& python -u (Join-Path $repo 'temp\p87_t.py') *> (Join-Path $repo 'temp\_p87_t.txt')
$rc = $LASTEXITCODE
"B rc=$rc $(Get-Date -Format HH:mm:ss.fff)" | Out-File -Append -Encoding utf8 $log
"end $(Get-Date -Format HH:mm:ss.fff)" | Out-File -Append -Encoding utf8 $log
