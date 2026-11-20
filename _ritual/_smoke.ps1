Set-Location 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
'SMOKE OK ' + (Get-Date).ToString('HH:mm:ss.fff') + ' pid ' + $PID |
    Out-File -FilePath '_smoke_out.txt' -Encoding ascii
Start-Sleep -Seconds 2
'SMOKE DONE' | Add-Content '_smoke_out.txt'
