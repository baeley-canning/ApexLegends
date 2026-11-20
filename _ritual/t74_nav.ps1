# t74_nav.ps1 - focus a browser window, navigate it to a URL, capture the result. One process.
param([int]$TargetPid, [string]$Url, [string]$Tag = 'nav')
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
& "$r\t45_focus.ps1" -TargetPid $TargetPid -W 1280 -H 940 | Out-Null
Get-Content "$r\_focus.txt"
& "$r\click.ps1" -X 512 -Y 59 | Out-Null
Start-Sleep -Milliseconds 500
& "$r\paste.ps1" -Text $Url | Out-Null
Start-Sleep -Milliseconds 400
& "$r\sendkey.ps1" -Keys 'ENTER' -Out "$r\_$($Tag)_key.txt" | Out-Null
Start-Sleep -Seconds 9
& "$r\t60_shot.ps1" -TargetPid $TargetPid -Tag $Tag -W 1280 -H 940 | Out-Null
