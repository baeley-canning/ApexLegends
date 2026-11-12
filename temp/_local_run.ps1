$ErrorActionPreference = 'Continue'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$sc = 'C:\Users\New User\OneDrive\Desktop\cheating\ext\qk_local.py'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_local2.txt'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_local_err.txt'
& $py $sc ("--out=" + $out) '--no-elevate' *> $log
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $log
