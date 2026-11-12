$ErrorActionPreference = 'Continue'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$sc = 'C:\Users\New User\OneDrive\Desktop\cheating\ext\qk_esp.py'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_esp1.txt'
& $py $sc '--local=kern30120' '--secs=90' '--fov=90' '--no-elevate' *> $out
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $out
