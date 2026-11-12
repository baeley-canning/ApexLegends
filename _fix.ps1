$f = 'C:\Users\New User\OneDrive\Desktop\cheating\_agents_scan.ps1'
(Get-Content $f) | ForEach-Object { $_ -replace '-FilePath (Join-Path', '-Path (Join-Path') } | Set-Content $f
Write-Host "done"
