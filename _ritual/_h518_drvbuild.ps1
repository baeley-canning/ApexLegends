Set-Location 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
& .\tools\BuildDriver.ps1 *> 'C:\p37vm\drvbuild.txt'
"EXIT=$LASTEXITCODE" | Add-Content 'C:\p37vm\drvbuild.txt'
