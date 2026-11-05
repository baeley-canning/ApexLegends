# p303_shell.ps1 - probe #303 (variable: Win+R first, Start flyout fallback - post-reboot session)
# p302's Explorer click did nothing (PCA dialog had focus). Win+R failed in the pre-reboot session but
# this is a fresh boot, so it is worth one attempt; Start flyout (dead pre-reboot) is the fallback.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p303.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Shot($n) { & $v controlvm $VM screenshotpng (Join-Path $d ('p303_' + $n + '.png')) 2>&1 | Out-Null }
Say 'START'
K @('winr'); Start-Sleep -Milliseconds 1500
K @('powershell'); Start-Sleep -Milliseconds 400; K @('enter')
Start-Sleep -Seconds 6
Shot 'r'
Say 'shot r'
$p = Join-Path $d 'p303_r.png'
$b1 = 0; if (Test-Path $p) { $b1 = (Get-Item $p).Length }
Say ('bytes r=' + $b1)
Start-Sleep -Seconds 2
Shot 'r2'
Say 'END'