$ErrorActionPreference = 'Continue'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$sc = 'C:\Users\New User\OneDrive\Desktop\cheating\ext\qk_name.py'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_verify1.txt'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_verify_err.txt'
& $py $sc '--needle=kern30120' '--verify' '--show=0' ("--out=" + $out) '--no-elevate' *> $log
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $log
