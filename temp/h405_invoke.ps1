$r='C:\Users\New User\Onedeve\\Desktop\\cheating'
$r='C:\Users\New User\OneDrive\\Desktop\\cheating'
$s=Join-Path $r 'temp\h405_invoke_inner.ps1'
"& '$r\\QwenKernPremium\\build\\h405_native.exe' '--pid','14624' *> '$r\\temp\\h405_invoke.txt'"|Set-Content -LiteralPath $s -Encoding ASCII
$p=Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Verb RunAs -Wait -PassThru
"rc=$($p.ExitCode)"|Add-Content "$r\\temp\\h405_invoke.txt"