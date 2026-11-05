# p272g - press Finish on the Completing page (Reboot now pre-selected) -> guest reboot only.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
& (Join-Path $base 'vm_type.ps1') -Seq 'enter'
Start-Sleep -Seconds 5
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'shot.ps1') 'p272g_1' | Out-Null
Start-Sleep -Seconds 20
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'shot.ps1') 'p272g_2' | Out-Null
Start-Sleep -Seconds 25
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'shot.ps1') 'p272g_3' | Out-Null
