$ErrorActionPreference = 'Continue'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$sc = 'C:\Users\New User\OneDrive\Desktop\cheating\ext\qk_name.py'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_name3.txt'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_name_err.txt'
& $py $sc '--needle=kern30120' '--probe' '--show=0' ("--out=" + $out) '--no-elevate' *> $log
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $log
