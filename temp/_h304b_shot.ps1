# _h304b_shot.ps1 - screenshot with an explicit display index (help: screenshotpng <filename> [display]).
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm = 'Win11-Test2'
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$log = Join-Path $d '_h304_shots.txt'
Set-Content -LiteralPath $log -Encoding ascii -Value ((Get-Date -f 'HH:mm:ss') + ' start')
foreach ($i in 0, 1) {
    $png = Join-Path $d ('_h304_d' + $i + '.png')
    Remove-Item -LiteralPath $png -Force -EA 0
    $t = (& $vb controlvm $vm screenshotpng $png $i 2>&1 | Out-String)
    $sz = 'FAIL'
    if (Test-Path $png) { $sz = (Get-Item $png).Length.ToString() }
    Add-Content -LiteralPath $log -Value ('disp' + $i + ' rc=' + $LASTEXITCODE + ' size=' + $sz + ' ' + ($t -replace '\s+', ' ').Trim()) -Encoding ascii
}
Add-Content -LiteralPath $log -Value 'done' -Encoding ascii
Get-Content -LiteralPath $log
