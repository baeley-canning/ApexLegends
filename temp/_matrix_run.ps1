$ErrorActionPreference = 'Continue'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$sc = 'C:\Users\New User\OneDrive\Desktop\cheating\ext\qk_name.py'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_matrix1.txt'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_matrix_err.txt'
& $py $sc '--needle=kern30120' '--matrix' '--show=0' '--w=1920' '--h=1080' ("--out=" + $out) '--no-elevate' *> $log
"exit=$LASTEXITCODE" | Add-Content -LiteralPath $log
