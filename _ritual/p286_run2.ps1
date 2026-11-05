# p286_run2.ps1 - probe #286 (variable: bare 'r' pressed while the flyout is already open)
# #285: batch winr again ended with only the Start flyout (#283b same). The flyout owns focus and
# drops every character, so the batched r never lands. Pressing Win+R while Start is ALREADY open
# is supposed to close it and open Run. So open Start first, let it settle 2 s, then send bare r
# twice - no payload, just shots.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p286.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Shot($n) { & $v controlvm $VM screenshotpng (Join-Path $d ('p286_' + $n + '.png')) 2>&1 | Out-Null; Say ('shot ' + $n) }

Say 'START'
K @('esc'); Start-Sleep -Milliseconds 900
K @('winr'); Start-Sleep -Seconds 2
Shot 'start'
K @('r'); Start-Sleep -Milliseconds 900
K @('r'); Start-Sleep -Seconds 2
Shot 'rr'
Say 'END'
