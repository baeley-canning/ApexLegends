$ErrorActionPreference = 'Continue'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvclean.txt'
"=== drvclean $(Get-Date -f 'HH:mm:ss') ===" | Set-Content -LiteralPath $log
$dst = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\drv_backup'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem 'C:\Windows\System32\drivers' -Filter 'apexdrv*' -ErrorAction SilentlyContinue | ForEach-Object {
    Move-Item -LiteralPath $_.FullName -Destination $dst -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $_.FullName) { Add-Content $log ("STILL THERE: " + $_.Name) }
    else { Add-Content $log ("moved: " + $_.Name) }
}
foreach ($s in 'ApexDrv', 'zapexdrv', 'kernprobe', 'apexdrv_cat') {
    $q = (& sc.exe query $s 2>&1 | Out-String)
    if ($q -match '1060') { Add-Content $log ("absent: " + $s) }
    else {
        Add-Content $log ("present: " + $s + " -> delete")
        (& sc.exe delete $s 2>&1 | Out-String) | ForEach-Object { Add-Content $log ("   " + $_.Trim()) }
    }
}
$left = @(Get-ChildItem 'C:\Windows\System32\drivers' -Filter 'apexdrv*' -ErrorAction SilentlyContinue).Count
Add-Content $log ("remaining apexdrv* files: " + $left)
