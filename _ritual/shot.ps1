param([Parameter(Mandatory=$true)][string]$Name)
# p269 helper: screenshot with retries, prints OK <path> on success. Read-only.
$v = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$p = Join-Path 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual' ($Name + '.png')
if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
for ($i = 1; $i -le 6; $i++) {
    & $v controlvm Win11-Test2 screenshotpng "$p" 2>$null | Out-Null
    Start-Sleep -Milliseconds 800
    if (Test-Path $p) { if ((Get-Item -LiteralPath $p).Length -gt 5000) { "OK $p"; exit 0 } }
    Start-Sleep -Seconds 1
}
"FAIL $p"; exit 1
