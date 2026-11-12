# temp\_probe_run.ps1 -- wrapper so the harness cannot eat python's traceback.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
"=== probe run $(Get-Date -Format HH:mm:ss) ===" | Set-Content "$root\temp\_probe_out.txt"
sc.exe start gdrv3 *>> "$root\temp\_probe_out.txt"
Start-Sleep -Seconds 2
& $py "$root\temp\_qk_dtb_probe.py" *>> "$root\temp\_probe_out.txt"
"rc=$LASTEXITCODE" | Add-Content "$root\temp\_probe_out.txt"
