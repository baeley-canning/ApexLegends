# p272f - press Install on the Custom Setup page (all features already ticked, incl. Direct3D).
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
& (Join-Path $base 'vm_type.ps1') -Seq 'enter'
Start-Sleep -Seconds 4
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'shot.ps1') 'p272f_1' | Out-Null
Start-Sleep -Seconds 8
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'shot.ps1') 'p272f_2' | Out-Null
