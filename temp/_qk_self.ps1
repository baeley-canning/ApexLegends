$ErrorActionPreference = 'Continue'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$sc = 'C:\Users\New User\OneDrive\Desktop\cheating\ext\qk_va.py'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_va_self.txt'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_qk3.out'
& $py $sc '--pid=23440' '--pe' ("--out=" + $out) '--no-elevate' *> $log
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $log
